enum StartupStage {
  opening('Opening Hyperstream'),
  preferences('Loading saved settings'),
  player('Starting the music player'),
  audioSession('Preparing audio'),
  volume('Restoring music volume'),
  account('Restoring your saved account');

  const StartupStage(this.label);
  final String label;
}
