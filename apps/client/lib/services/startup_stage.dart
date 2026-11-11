enum StartupStage {
  opening('Opening Hyperstream'),
  preferences('Loading saved settings'),
  player('Starting the music player'),
  audioSession('Preparing audio'),
  volume('Restoring music volume');

  const StartupStage(this.label);
  final String label;
}
