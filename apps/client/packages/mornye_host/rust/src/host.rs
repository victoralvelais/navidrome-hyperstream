use mornye_extensions::environment::ExtensionEnvironment;
use mornye_extensions::ffmpeg::CommandResult;
use mornye_extensions::package::ExtensionPackage;
use mornye_extensions::{ExtensionRuntime, RuntimeLimits};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

type Slot = Arc<Mutex<Option<Arc<ExtensionRuntime>>>>;
pub struct Host {
    environment: ExtensionEnvironment,
    packages: PathBuf,
    downloads: PathBuf,
    runtimes: Mutex<HashMap<String, Slot>>,
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (tempfile::TempDir, Host) {
        let root = tempfile::tempdir().unwrap();
        let host = Host::new(
            &json!({"root":root.path(),"key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}),
        )
        .unwrap();
        let dir = host.directory("tidal-web").unwrap();
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("manifest.json"), json!({
            "name":"tidal-web","version":"1.2.14","displayName":"Test source", "description":"Synthetic test provider", "author":"Hyperstream tests",
            "type":["metadata_provider","download_provider"],"minAppVersion":"5.3.0",
            "permissions":{"network":["example.test"],"storage":true,"file":true}
        }).to_string()).unwrap();
        fs::write(dir.join("index.js"), r#"
            function fetchDownloadInfo(id, quality) {
                return {kind:'direct',directURL:'https://example.test/'+id+'.flac'};
            }
            function inferOutputExtension() { return '.flac'; }
            registerExtension({
                getTrack:function(id) { if(id === 'loop') { while(true) {} } return {id:id,name:'Song'}; },
                download:function(id,q,p,progress) { progress(50); var write=file.write(p,id); return write.success ? {success:true,file_path:p} : write; }
            });
        "#).unwrap();
        host.environment
            .set_setting("tidal-web", "_hyperstream_enabled", json!(true))
            .unwrap();
        (root, host)
    }
    fn call(method: &str, args: Value, id: &str) -> Value {
        json!({"op":"call","id":"tidal-web","method":method,"args":args,"request_id":id})
    }
    fn soundcloud_fixture() -> (tempfile::TempDir, Host) {
        let (root, host) = fixture();
        let dir = host.directory("soundcloud").unwrap();
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("manifest.json"),
            json!({
                "name":"soundcloud","version":"1.0.15","displayName":"SoundCloud test",
                "description":"Synthetic test provider", "author":"Hyperstream tests",
                "type":["metadata_provider","download_provider"],"minAppVersion":"4.9.1",
                "permissions":{"network":["example.test"],"storage":true,"file":true}
            })
            .to_string(),
        )
        .unwrap();
        fs::write(
            dir.join("index.js"),
            include_str!("../tests/fixtures/soundcloud.js"),
        )
        .unwrap();
        host.environment
            .set_setting("soundcloud", "_hyperstream_enabled", json!(true))
            .unwrap();
        (root, host)
    }
    fn sc_call(method: &str, args: Value) -> Value {
        json!({"op":"call","id":"soundcloud","method":method,"args":args,"request_id":"soundcloud-test"})
    }
    #[test]
    fn soundcloud_preserves_interleaved_playlist_positions_and_repeated_uploads() {
        let (_root, host) = soundcloud_fixture();
        let result = host
            .call(&sc_call("getPlaylist", json!(["complete"])))
            .unwrap();
        let tracks = result["tracks"].as_array().unwrap();
        assert_eq!(result["total_tracks"], 4);
        assert_eq!(
            tracks
                .iter()
                .map(|t| t["id"].as_str().unwrap())
                .collect::<Vec<_>>(),
            vec!["102", "101", "102", "103"]
        );
        assert_eq!(
            tracks
                .iter()
                .map(|t| t["track_number"].as_u64().unwrap())
                .collect::<Vec<_>>(),
            vec![1, 2, 3, 4]
        );
        for id in ["missing", "failed", "count"] {
            assert!(host.call(&sc_call("getPlaylist", json!([id]))).is_err());
        }
    }
    #[test]
    fn soundcloud_streams_progressive_audio_or_prepares_hls_and_rejects_previews() {
        let (_root, host) = soundcloud_fixture();
        let direct = host
            .call(&sc_call("hyperstreamResolve", json!(["1", "aac_160"])))
            .unwrap();
        assert_eq!(direct["url"], "https://example.test/audio");
        assert_eq!(direct["format"], "mp3");
        assert_eq!(direct["prepareOnFailure"], true);
        assert!(direct.get("bitrate_kbps").is_none());
        let with_bitrate = host
            .call(&sc_call("hyperstreamResolve", json!(["6", "aac_160"])))
            .unwrap();
        assert_eq!(with_bitrate["bitrate_kbps"], 128);
        assert_eq!(
            host.call(&sc_call("hyperstreamResolve", json!(["2", "aac_160"])))
                .unwrap(),
            json!({"prepare":true})
        );
        for id in ["3", "4", "5"] {
            let track = host.call(&sc_call("getTrack", json!([id]))).unwrap();
            assert_eq!(track["is_playable"], false);
            let audio = host
                .call(&sc_call("hyperstreamResolve", json!([id, "aac_160"])))
                .unwrap();
            assert_eq!(audio["error_code"], "track_unavailable");
        }
    }
    #[test]
    fn soundcloud_download_uses_existing_private_file_grant() {
        let (root, host) = soundcloud_fixture();
        let dir = root.path().join("downloads").join("soundcloud");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("source.m4a");
        let result = host
            .call(
                &json!({"op":"download", "id":"soundcloud", "method":"hyperstreamDownload",
            "args":["2", "aac_160", path], "directory":dir,"request_id":"soundcloud-download"}),
            )
            .unwrap();
        assert_eq!(result["success"], true);
        assert_eq!(fs::read_to_string(path).unwrap(), "synthetic audio 2");
        assert_eq!(
            host.call(&sc_call(
                "hyperstreamDownload",
                json!(["3", "aac_160", "unused"])
            ))
            .unwrap()["error_code"],
            "track_unavailable"
        );
    }
    fn qobuz_fixture() -> (tempfile::TempDir, Host) {
        let (root, host) = fixture();
        let dir = host.directory("qobuz-web").unwrap();
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("manifest.json"),
            json!({
                "name":"qobuz-web","version":"1.2.27","displayName":"Qobuz test",
                "description":"Synthetic test provider","author":"Hyperstream tests",
                "type":["metadata_provider","download_provider"],"minAppVersion":"5.3.0",
                "permissions":{"network":["example.test"],"storage":true,"file":true}
            })
            .to_string(),
        )
        .unwrap();
        fs::write(
            dir.join("index.js"),
            include_str!("../tests/fixtures/qobuz.js"),
        )
        .unwrap();
        host.environment
            .set_setting("qobuz-web", "_hyperstream_enabled", json!(true))
            .unwrap();
        (root, host)
    }
    fn qobuz_call(method: &str, args: Value) -> Value {
        json!({"op":"call","id":"qobuz-web","method":method,"args":args,"request_id":"qobuz-test"})
    }
    #[test]
    fn qobuz_reports_each_failed_candidate_and_restores_fetch() {
        let (_root, host) = qobuz_fixture();
        let failed = host
            .call(&qobuz_call(
                "hyperstreamResolve",
                json!(["unavailable", "27"]),
            ))
            .unwrap();
        assert_eq!(failed["success"], false);
        assert_eq!(
            failed["error_message"],
            "All audio providers failed: Candidate timed out"
        );
        assert_eq!(
            failed["provider_failures"],
            json!([
                {"candidate":1,"quality":"27","message":"Candidate unavailable","code":"fixture_unavailable","retry_mode":"none"},
                {"candidate":2,"quality":"27","message":"Candidate timed out","code":"fixture_timeout","retry_mode":"retry"}
            ])
        );
        let state = host
            .call(&qobuz_call("getTrack", json!(["state"])))
            .unwrap();
        assert_eq!(state["fetchRestored"], true);
        assert_eq!(
            state["attempts"],
            json!([
                {"provider":"first","id":"unavailable","quality":"27"},
                {"provider":"second","id":"unavailable","quality":"27"}
            ])
        );

        let audio = host
            .call(&qobuz_call("hyperstreamResolve", json!(["selected", "6"])))
            .unwrap();
        assert_eq!(
            audio,
            json!({"url":"https://example.test/selected.flac","format":"flac"})
        );
        let state = host
            .call(&qobuz_call("getTrack", json!(["state"])))
            .unwrap();
        assert_eq!(state["fetchRestored"], true);
        assert_eq!(
            &state["attempts"].as_array().unwrap()[2..],
            &[
                json!({"provider":"first","id":"selected","quality":"6"}),
                json!({"provider":"second","id":"selected","quality":"6"})
            ]
        );
    }
    #[test]
    fn qobuz_propagates_verification_and_resolves_on_the_next_call() {
        let (_root, host) = qobuz_fixture();
        let verification = host
            .call(&qobuz_call("hyperstreamResolve", json!(["verify", "7"])))
            .unwrap_err();
        assert!(verification.contains("E_SESSION_VERIFICATION_REQUIRED"));
        let audio = host
            .call(&qobuz_call("hyperstreamResolve", json!(["selected", "7"])))
            .unwrap();
        assert_eq!(
            audio,
            json!({"url":"https://example.test/selected.flac","format":"flac"})
        );
    }
    fn youtube_fixture() -> (tempfile::TempDir, Host) {
        let (root, host) = fixture();
        let dir = host.directory("ytmusic-spotiflac").unwrap();
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("manifest.json"), json!({
            "name":"ytmusic-spotiflac","version":"2.4.7","displayName":"YouTube test", "description":"Synthetic test provider", "author":"Hyperstream tests",
            "type":["metadata_provider","download_provider"],"minAppVersion":"4.5.1",
            "permissions":{"network":["example.test"],"storage":true,"file":true}
        }).to_string()).unwrap();
        fs::write(dir.join("index.js"), r#"
            function requestInnerTubeAudioDownload(id) {
                if (id === 'failed') throw new Error('provider unavailable');
                return {extension:'.opus', url:'https://example.test/opus', bitrate:160000, alternatives:
                    id === 'opus' ? [] : [{extension:'.m4a', url:'https://example.test/'+id,
                        ua:'Synthetic client', bitrate:id === 'invalid-bitrate' ? 10000001 : 127600}]};
            }
            function waitUntilAvailable() { return true; }
            function fetchVideoMetadataSync(id) { return {id:id, title:'User upload', duration:150}; }
            function sanitizeTrackBeforeReturn(t) { return {id:t.id, name:t.title || 'Upload', duration_ms:(t.duration || 0)*1000}; }
            var CONFIG = {clientVersion:'synthetic'}, MAX_CONTINUATION_PAGES = 2;
            var fixtureMode = '';
            function getRandomUserAgent() { return 'Synthetic client'; }
            function fetchJSONSync(url, options) { fixtureMode = JSON.parse(options.body).browseId; return {}; }
            function parseBrowseResponse() { return {name:'Practice', album:{total_tracks:4}, tracks:[{id:'a'},{id:'b'}], _continuationToken:'page2'}; }
            function fetchContinuationSync() { return fixtureMode === 'VLbroken' ? null : {}; }
            function parseContinuationResponse() { return {tracks:[{id:'a'},{id:'c'}], continuationToken:fixtureMode === 'VLloop' ? 'page2' : null}; }
            function parseItemExtended(t) { return t; }
            function applyBrowseCollectionMetadata() {}
            function searchFixture(query, options) {
                var videos = options && options.filter === 'videos';
                if (query === 'both-fail' || (query === 'general-fails' && !videos) || (query === 'videos-fail' && videos))
                    throw new Error('Synthetic category failure');
                return videos ? [
                    {id:'creator-upload', name:'First Artist x Second Artist Mashup', artists:'Independent Creator', item_type:'track'},
                    {id:'shared', name:'Same upload', item_type:'track'},
                    {id:'different-upload', name:'First Artist x Second Artist Mashup', item_type:'track'}
                ] : [
                    {id:'studio', name:'Catalog song', artists:'First Artist', item_type:'track'},
                    {id:'shared', name:'Same upload', item_type:'track'},
                    {id:'album', name:'Catalog album', item_type:'album'}
                ];
            }
            registerExtension({getTrack:function() { return {title:'Loading...'}; }, customSearch:searchFixture});
        "#).unwrap();
        host.environment
            .set_setting("ytmusic-spotiflac", "_hyperstream_enabled", json!(true))
            .unwrap();
        (root, host)
    }
    #[test]
    fn youtube_search_merges_creator_videos_with_catalog_results_without_duplicate_uploads() {
        let (_root, host) = youtube_fixture();
        let request = |query, options| json!({"op":"call","id":"ytmusic-spotiflac","method":"customSearch", "args":[query, options],"request_id":"search"});
        let results = host
            .call(&request("mashup", json!({"type":"all","limit":30})))
            .unwrap();
        let rows = results.as_array().unwrap();
        let ids: Vec<_> = rows.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert_eq!(
            ids,
            vec![
                "studio",
                "creator-upload",
                "shared",
                "album",
                "different-upload"
            ]
        );
        assert_eq!(rows[1]["artists"], "Independent Creator");
        assert_eq!(rows[3]["item_type"], "album");
        let bounded = host.call(&request("mashup", json!({"limit":2}))).unwrap();
        assert_eq!(bounded.as_array().unwrap().len(), 2);
        assert_eq!(bounded[1]["id"], "creator-upload");
        let filtered = host
            .call(&request("mashup", json!({"filter":"videos"})))
            .unwrap();
        assert_eq!(filtered.as_array().unwrap().len(), 3);
        assert_eq!(filtered[0]["id"], "creator-upload");
    }
    #[test]
    fn youtube_search_keeps_the_successful_category_when_the_other_fails() {
        let (_root, host) = youtube_fixture();
        let request = |query| json!({"op":"call","id":"ytmusic-spotiflac","method":"customSearch", "args":[query, {"limit":30}],"request_id":"search"});
        assert_eq!(
            host.call(&request("general-fails")).unwrap()[0]["id"],
            "creator-upload"
        );
        assert_eq!(
            host.call(&request("videos-fail")).unwrap()[0]["id"],
            "studio"
        );
        let error = host.call(&request("both-fail")).unwrap_err();
        assert!(
            error.contains("Synthetic category failure"),
            "The pinned runtime should preserve the thrown JavaScript message"
        );
    }
    #[test]
    fn youtube_stream_uses_m4a_with_request_context_or_prepares_audio() {
        let (_root, host) = youtube_fixture();
        let resolve = |id| {
            host.call(&json!({"op":"call","id":"ytmusic-spotiflac","method":"hyperstreamResolve", "args":[id,"best"],"request_id":id})).unwrap()
        };
        let direct = resolve("exact-upload");
        assert_eq!(direct["url"], "https://example.test/exact-upload");
        assert_eq!(direct["headers"]["User-Agent"], "Synthetic client");
        assert_eq!(direct["prepareOnFailure"], true);
        assert_eq!(direct["bitrate_kbps"], 128);
        assert!(resolve("invalid-bitrate").get("bitrate_kbps").is_none());
        assert_eq!(resolve("opus"), json!({"prepare":true}));
        assert_eq!(resolve("failed"), json!({"prepare":true}));
    }
    #[test]
    fn youtube_pasted_upload_returns_metadata_without_placeholder_or_matching() {
        let (_root, host) = youtube_fixture();
        let track = host.call(&json!({"op":"call","id":"ytmusic-spotiflac","method":"getTrack", "args":["abcdefghijk"],"request_id":"track"})).unwrap();
        assert_eq!(
            track,
            json!({"id":"abcdefghijk", "name":"User upload", "duration_ms":150000})
        );
    }
    #[test]
    fn youtube_playlist_pagination_preserves_repeats_and_rejects_partial_pages() {
        let (_root, host) = youtube_fixture();
        let request = |id| json!({"op":"call","id":"ytmusic-spotiflac","method":"getPlaylist", "args":[id],"request_id":id});
        let playlist = host.call(&request("practice")).unwrap();
        assert_eq!(playlist["total_tracks"], 4);
        let ids: Vec<_> = playlist["tracks"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, vec!["a", "b", "a", "c"]);
        assert!(host.call(&request("broken")).is_err());
        assert!(host.call(&request("loop")).is_err());
    }
    #[test]
    fn real_js_adapter_resolves_and_preserves_identity() {
        let (_root, host) = fixture();
        assert_eq!(
            host.call(&call("getTrack", json!(["123"]), "one")).unwrap()["id"],
            "123"
        );
        assert_eq!(
            host.call(&call("hyperstreamResolve", json!(["123", "HIGH"]), "two"))
                .unwrap()["url"],
            "https://example.test/123.flac"
        );
    }
    #[test]
    fn rejects_unverified_package_and_unknown_provider() {
        let (root, host) = fixture();
        let bad = root.path().join("bad.sflx");
        fs::write(&bad, b"not the expected archive").unwrap();
        assert!(
            host.call(&json!({"op":"install","id":"qobuz-web","path":bad}))
                .unwrap_err()
                .contains("checksum")
        );
        assert!(
            host.call(&json!({"op":"enable","id":"../outside","enabled":true}))
                .is_err()
        );
    }
    #[test]
    fn cancellation_before_dispatch_retires_vm_and_retry_works() {
        let (_root, host) = fixture();
        host.call(&json!({"op":"cancel","request_id":"cancelled"}))
            .unwrap();
        assert!(
            host.call(&call("getTrack", json!(["loop"]), "cancelled"))
                .is_err()
        );
        assert_eq!(
            host.call(&call("getTrack", json!(["retry"]), "fresh"))
                .unwrap()["id"],
            "retry"
        );
    }
    #[test]
    fn disabling_provider_blocks_cached_runtime() {
        let (_root, host) = fixture();
        host.call(&call("getTrack", json!(["123"]), "one")).unwrap();
        host.call(&json!({"op":"enable","id":"tidal-web","enabled":false}))
            .unwrap();
        assert!(host.call(&call("getTrack", json!(["123"]), "two")).is_err());
    }
    #[test]
    fn encrypted_settings_survive_restart_without_plaintext_secret() {
        let (root, host) = fixture();
        host.call(&json!({"op":"save_settings","id":"tidal-web","values":{"apiKey":"synthetic-secret-123"}})).unwrap();
        fn inspect(dir: &Path) {
            for file in fs::read_dir(dir).unwrap() {
                let file = file.unwrap();
                if file.file_type().unwrap().is_dir() {
                    inspect(&file.path());
                } else {
                    assert!(
                        !String::from_utf8_lossy(&fs::read(file.path()).unwrap())
                            .contains("synthetic-secret-123")
                    );
                }
            }
        }
        inspect(&root.path().join("data"));
        drop(host);
        let reopened = Host::new(
            &json!({"root":root.path(),"key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}),
        )
        .unwrap();
        assert_eq!(
            reopened.environment.settings("tidal-web").unwrap()["apiKey"],
            "synthetic-secret-123"
        );
    }
    #[test]
    fn grant_requires_pending_owned_callback() {
        let (_root, host) = fixture();
        assert!(
            host.call(
                &json!({"op":"grant","id":"tidal-web","state":"unowned","grant":"synthetic"})
            )
            .is_err()
        );
    }
    #[test]
    fn download_grants_reject_non_staging_directory() {
        let (root, host) = fixture();
        let request = json!({"op":"download","id":"tidal-web","method":"hyperstreamDownload", "request_id":"one",
            "directory":root.path(), "args":["123","LOSSLESS",root.path().join("outside.flac")]});
        assert!(
            host.call(&request)
                .unwrap_err()
                .contains("outside the private staging")
        );
    }
    #[test]
    fn download_grant_accepts_native_path_alias_and_is_revoked_after_call() {
        let (root, host) = fixture();
        let job = root.path().join("downloads").join("audio-test");
        fs::create_dir_all(&job).unwrap();
        let output = job.join("source.flac");
        let request = json!({"op":"download","id":"tidal-web","method":"hyperstreamDownload","request_id":"one",
            "directory":job,"args":["123","LOSSLESS",output]});
        assert_eq!(host.call(&request).unwrap()["success"], true);
        assert_eq!(fs::read_to_string(&output).unwrap(), "123");
        // An ordinary call has no temporary download grant.
        assert_eq!(
            host.call(&call(
                "hyperstreamDownload",
                json!(["blocked", "LOSSLESS", output]),
                "two"
            ))
            .unwrap()["success"],
            false
        );
        assert_eq!(fs::read_to_string(&output).unwrap(), "123");
    }
}
fn text<'a>(v: &'a Value, key: &str) -> Result<&'a str, String> {
    v[key].as_str().ok_or_else(|| format!("Missing {key}"))
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn catalog() -> Vec<Value> {
    serde_json::from_str(include_str!("../../assets/catalog.json")).unwrap()
}
fn entry(id: &str) -> Result<Value, String> {
    catalog()
        .into_iter()
        .find(|e| e["id"] == id)
        .ok_or("Unsupported provider".into())
}
impl Host {
    pub fn new(request: &Value) -> Result<Self, String> {
        let root = Path::new(text(request, "root")?);
        fs::create_dir_all(root).map_err(err)?;
        let root = fs::canonicalize(root).map_err(err)?;
        let packages = root.join("packages");
        let downloads = root.join("downloads");
        fs::create_dir_all(&packages).map_err(err)?;
        fs::create_dir_all(&downloads).map_err(err)?;
        // Only this host owns these per-attempt directories. A cold start has
        // no live transfers; remove leftovers from a previous interrupted run.
        for item in fs::read_dir(&downloads).map_err(err)? {
            let item = item.map_err(err)?;
            let name = item.file_name().to_string_lossy().into_owned();
            if item.file_type().map_err(err)?.is_dir()
                && (name.starts_with("audio-") || name.starts_with("install-"))
            {
                fs::remove_dir_all(item.path()).map_err(err)?;
            }
        }
        // Compatibility version of the embedded runtime, separate from the app
        // version. Required-feature gates remain active.
        let environment =
            ExtensionEnvironment::new(&root.join("data"), text(request, "key")?, "5.3.1")
                .map_err(err)?;
        Ok(Self {
            environment,
            packages,
            downloads,
            runtimes: Mutex::default(),
        })
    }
    fn directory(&self, id: &str) -> Result<PathBuf, String> {
        let e = entry(id)?;
        Ok(self
            .packages
            .join(format!("{}-{}", id, text(&e, "version")?)))
    }
    fn slot(&self, id: &str) -> Slot {
        self.runtimes
            .lock()
            .unwrap()
            .entry(id.into())
            .or_default()
            .clone()
    }
    fn runtime(
        &self,
        id: &str,
        slot: &mut Option<Arc<ExtensionRuntime>>,
    ) -> Result<Arc<ExtensionRuntime>, String> {
        if let Some(runtime) = slot {
            return Ok(runtime.clone());
        }
        let dir = self.directory(id)?;
        if !self.enabled(id)? {
            return Err("Enable this provider in Music sources".into());
        }
        let manifest: Value =
            serde_json::from_str(&fs::read_to_string(dir.join("manifest.json")).map_err(err)?)
                .map_err(err)?;
        // Preserve the provider's callback protocol. The scoped authentication
        // browser captures it without registering that scheme globally.
        let source = fs::read_to_string(dir.join("index.js")).map_err(err)?;
        let source = format!("{}\n{}", include_str!("adapter.js"), source);
        let runtime = self
            .environment
            .load(&manifest.to_string(), &source, RuntimeLimits::default())
            .map_err(err)?;
        *slot = Some(runtime.clone());
        Ok(runtime)
    }
    fn enabled(&self, id: &str) -> Result<bool, String> {
        Ok(self
            .environment
            .settings(id)
            .map_err(err)?
            .get("_hyperstream_enabled")
            == Some(&Value::Bool(true)))
    }
    pub fn call(&self, r: &Value) -> Result<Value, String> {
        match text(r, "op")? {
            "list" => {
                return Ok(Value::Array(
                    catalog()
                        .into_iter()
                        .map(|mut e| {
                            let id = e["id"].as_str().unwrap().to_owned();
                            e["installed"] =
                                json!(self.directory(&id).unwrap().join("index.js").is_file());
                            e["enabled"] = json!(self.enabled(&id).unwrap_or(false));
                            e
                        })
                        .collect(),
                ));
            }
            "ffmpeg_poll" => {
                return serde_json::from_str(
                    &self
                        .environment
                        .ffmpeg_commands()
                        .wait_pending_json(0)
                        .map_err(err)?,
                )
                .map_err(err);
            }
            "ffmpeg_active" => {
                return Ok(json!(
                    self.environment
                        .ffmpeg_commands()
                        .get(text(r, "command_id")?)
                        .map_err(err)?
                        .is_some()
                ));
            }
            "ffmpeg_complete" => {
                self.environment
                    .ffmpeg_commands()
                    .complete(
                        text(r, "command_id")?,
                        CommandResult {
                            success: r["success"] == true,
                            output: r["output"].as_str().unwrap_or("").into(),
                            error: r["error"].as_str().unwrap_or("").into(),
                        },
                    )
                    .map_err(err)?;
                return Ok(Value::Null);
            }
            "cancel" => {
                self.environment
                    .download_state()
                    .cancellation
                    .cancel(text(r, "request_id")?)
                    .map_err(err)?;
                return Ok(Value::Null);
            }
            _ => {}
        }
        let id = text(r, "id")?;
        let expected = entry(id)?;
        if r["op"] == "pending" {
            return serde_json::to_value(self.environment.pending_auth(id).map_err(err)?)
                .map_err(err);
        }
        let slot = self.slot(id);
        let mut slot = slot.lock().map_err(|_| "Provider lock failed")?;
        match text(r, "op")? {
            "install" => {
                let path = Path::new(text(r, "path")?);
                let bytes = fs::read(path).map_err(err)?;
                let hash: String = Sha256::digest(&bytes)
                    .iter()
                    .map(|b| format!("{b:02x}"))
                    .collect();
                if bytes.len() > 16 * 1024 * 1024 || hash != text(&expected, "sha256")? {
                    return Err("Provider package checksum did not match".into());
                }
                let mut package = ExtensionPackage::open(path).map_err(err)?;
                if package.manifest.name != id
                    || package.manifest.version != text(&expected, "version")?
                {
                    return Err("Provider package identity did not match".into());
                }
                let destination = self.directory(id)?;
                if !destination.exists() {
                    let staging = tempfile::tempdir_in(&self.packages).map_err(err)?;
                    package.extract(staging.path(), &|| Ok(())).map_err(err)?;
                    fs::rename(staging.path(), destination).map_err(err)?;
                }
                self.environment
                    .set_setting(id, "_hyperstream_enabled", json!(true))
                    .map_err(err)?;
                Ok(Value::Null)
            }
            "enable" => {
                self.environment
                    .set_setting(id, "_hyperstream_enabled", r["enabled"].clone())
                    .map_err(err)?;
                if let Some(runtime) = slot.take() {
                    runtime.shutdown();
                }
                Ok(Value::Null)
            }
            "settings" => {
                let manifest: Value = serde_json::from_str(
                    &fs::read_to_string(self.directory(id)?.join("manifest.json")).map_err(err)?,
                )
                .map_err(err)?;
                Ok(
                    json!({"fields":manifest["settings"],"values":self.environment.settings(id).map_err(err)?}),
                )
            }
            "save_settings" => {
                for (key, value) in r["values"].as_object().ok_or("Missing settings")? {
                    if !key.starts_with('_') {
                        self.environment
                            .set_setting(id, key, value.clone())
                            .map_err(err)?;
                    }
                }
                if let Some(runtime) = slot.take() {
                    runtime.shutdown();
                }
                Ok(Value::Null)
            }
            op => {
                let runtime = self.runtime(id, &mut slot)?;
                let result = (|| match op {
                    "verify" => {
                        runtime
                            .preflight_signed_session(None, 60_000)
                            .map_err(err)?;
                        serde_json::to_value(self.environment.pending_auth(id).map_err(err)?)
                            .map_err(err)
                    }
                    "grant" => {
                        let owner = self
                            .environment
                            .resolve_callback_state(text(r, "state")?, false)
                            .map_err(err)?;
                        if owner != id {
                            return Err("Verification belongs to a different provider".into());
                        }
                        self.environment
                            .set_session_grant(id, text(r, "grant")?)
                            .map_err(err)?;
                        let value = runtime
                            .call("hyperstreamCompleteGrant", "[]", None, 60_000)
                            .map_err(err)?;
                        serde_json::from_str(&value).map_err(err)
                    }
                    "call" | "download" => {
                        let request_id = text(r, "request_id")?;
                        let lease = Arc::new(
                            self.environment
                                .download_state()
                                .cancellation
                                .acquire(request_id)
                                .map_err(err)?,
                        );
                        let method = text(r, "method")?;
                        if ![
                            "getTrack",
                            "getAlbum",
                            "getPlaylist",
                            "handleUrl",
                            "searchTracks",
                            "customSearch",
                            "checkAvailability",
                            "hyperstreamResolve",
                            "hyperstreamDownload",
                        ]
                        .contains(&method)
                        {
                            return Err("Unsupported provider operation".into());
                        }
                        if [
                            "checkAvailability",
                            "hyperstreamResolve",
                            "hyperstreamDownload",
                        ]
                        .contains(&method)
                            && runtime
                                .preflight_signed_session(Some(lease.clone()), 60_000)
                                .map_err(err)?
                        {
                            return Ok(json!({"needs_verification":true}));
                        }
                        let args = r["args"].to_string();
                        let value = if op == "download" {
                            let requested_directory = Path::new(text(r, "directory")?);
                            let directory = fs::canonicalize(requested_directory).map_err(err)?;
                            if !directory.starts_with(&self.downloads)
                                || directory == self.downloads
                            {
                                return Err(
                                    "Download directory is outside the private staging area".into(),
                                );
                            }
                            let _grant = self
                                .environment
                                .grant_temporary_download_directory(requested_directory)?;
                            runtime
                                .call_download(method, &args, Some(lease), 120_000)
                                .map_err(err)?
                        } else {
                            runtime
                                .call(method, &args, Some(lease), 60_000)
                                .map_err(err)?
                        };
                        serde_json::from_str(&value).map_err(err)
                    }
                    _ => Err("Unknown operation".into()),
                })();
                if result.is_err() {
                    runtime.shutdown();
                    *slot = None;
                }
                result
            }
        }
    }
}
