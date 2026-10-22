$ErrorActionPreference = 'Stop'
$clips = @(
    @{Id='idle_03_bored_blink';Folder='idle'},
    @{Id='idle_07_daydream';Folder='idle'},
    @{Id='idle_06_sideeye';Folder='idle'},
    @{Id='listening_02_curious';Folder='assistant'},
    @{Id='thinking_01_chin';Folder='assistant'},
    @{Id='speaking_01_explaining';Folder='assistant'},
    @{Id='happy_01_smile';Folder='personality_emotions'}
)
foreach ($clip in $clips) {
    & "$PSScriptRoot/prepare_navi_matte.ps1" `
        -Source ('assets/videos/' + $clip.Folder + '/' + $clip.Id + '.mp4') `
        -Animation ('assets/animations/' + $clip.Id + '.webp') `
        -Poster ('assets/images/' + $clip.Id + '.png')
}
