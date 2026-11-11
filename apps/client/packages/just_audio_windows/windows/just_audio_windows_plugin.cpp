#pragma comment(lib, "windowsapp")

#include "include/just_audio_windows/just_audio_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

#include "player.hpp"
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Media.Devices.h>

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// static std::unordered_map<std::string, AudioPlayer> players;
std::vector<std::unique_ptr<AudioPlayer>> players_;
using winrt::Windows::Devices::Enumeration::DeviceInformation;
DeviceInformation selected_output{nullptr};

// Resumes on Flutter's platform apartment before touching players or replying.
winrt::fire_and_forget HandleOutputs(
    std::string method, std::string requested_id,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    const auto devices = co_await DeviceInformation::FindAllAsync(
        winrt::Windows::Media::Devices::MediaDevice::GetAudioRenderSelector());
    if (method == "setOutput") {
      DeviceInformation chosen{nullptr};
      for (const auto& device : devices) {
        if (winrt::to_string(device.Id()) == requested_id) chosen = device;
      }
      if (!requested_id.empty() && !chosen) {
        result->Error("unavailable", "This output is no longer available.");
        co_return;
      }
      for (const auto& player : players_) player->mediaPlayer.AudioDevice(chosen);
      selected_output = chosen;
      result->Success();
      co_return;
    }
    bool still_present = !selected_output;
    for (const auto& device : devices) {
      if (selected_output && device.Id() == selected_output.Id()) still_present = true;
    }
    if (!still_present) {
      for (const auto& player : players_) player->mediaPlayer.AudioDevice(nullptr);
      selected_output = nullptr;
    }
    flutter::EncodableList outputs;
    outputs.push_back(EncodableMap{
      {EncodableValue("id"), EncodableValue("")},
      {EncodableValue("name"), EncodableValue("System default")},
      {EncodableValue("selected"), EncodableValue(!selected_output)}});
    for (const auto& device : devices) {
      outputs.push_back(EncodableMap{
        {EncodableValue("id"), EncodableValue(winrt::to_string(device.Id()))},
        {EncodableValue("name"), EncodableValue(winrt::to_string(device.Name()))},
        {EncodableValue("selected"), EncodableValue(selected_output && device.Id() == selected_output.Id())}});
    }
    result->Success(outputs);
  } catch (...) {
    result->Error("output_error", "Could not change or read audio outputs.");
  }
}

class JustAudioWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  JustAudioWindowsPlugin();

  virtual ~JustAudioWindowsPlugin();

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      flutter::BinaryMessenger* messenger);
  // Loops through cameras and returns camera
  // with matching camera_id or nullptr.
  AudioPlayer* GetPlayerByPlayerId(std::string id);

  // Disposes camera by camera id.
  void DisposePlayerByPlayerId(std::string id);
};

// static
void JustAudioWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.ryanheise.just_audio.methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<JustAudioWindowsPlugin>();
  auto outputs = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "dev.hyperstream/audio_outputs",
      &flutter::StandardMethodCodec::GetInstance());
  outputs->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "getOutputs" && call.method_name() != "setOutput") {
      result->NotImplemented();
      return;
    }
    std::string id;
    if (call.method_name() == "setOutput") {
      const auto* requested = std::get_if<std::string>(call.arguments());
      if (!requested) { result->Error("argument_error", "Choose an audio output."); return; }
      id = *requested;
    }
    HandleOutputs(call.method_name(), id, std::move(result));
  });

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get(), messenger_pointer = registrar->messenger()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result), std::move(messenger_pointer));
      });

  registrar->AddPlugin(std::move(plugin));
}

JustAudioWindowsPlugin::JustAudioWindowsPlugin() {}

JustAudioWindowsPlugin::~JustAudioWindowsPlugin() {}

void JustAudioWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    flutter::BinaryMessenger* messenger) {
  const auto* args =std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (args) {
    if (method_call.method_name().compare("init") == 0) {
      const auto* id = std::get_if<std::string>(ValueOrNull(*args, "id"));
      if (!id) {
        return result->Error("argument_error", "id argument missing");
      }
      auto player = std::make_unique<AudioPlayer>(*id, messenger);
      if (selected_output) player->mediaPlayer.AudioDevice(selected_output);
      players_.push_back(std::move(player));
      result->Success();
    } else if (method_call.method_name().compare("disposePlayer") == 0) {
      const auto* id = std::get_if<std::string>(ValueOrNull(*args, "id"));
      if (!id) {
        return result->Error("argument_error", "id argument missing");
      }
      DisposePlayerByPlayerId(*id);
      result->Success(flutter::EncodableMap());
    } else if (method_call.method_name().compare("disposeAllPlayers") == 0) {
      players_.clear();
      result->Success(flutter::EncodableMap());
    } else {
      result->NotImplemented();
    }
  } else {
    result->NotImplemented();
  }
}

AudioPlayer* JustAudioWindowsPlugin::GetPlayerByPlayerId(std::string id) {
  for (auto it = begin(players_); it != end(players_); ++it) {
    if ((*it)->HasPlayerId(id)) {
      return it->get();
    }
  }
  return nullptr;
}

void JustAudioWindowsPlugin::DisposePlayerByPlayerId(std::string id) {
  for (auto it = begin(players_); it != end(players_); ++it) {
    if ((*it)->HasPlayerId(id)) {
      players_.erase(it);
      return;
    }
  }
}

}  // namespace

void JustAudioWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  JustAudioWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
