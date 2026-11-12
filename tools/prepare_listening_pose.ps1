$ErrorActionPreference = 'Stop'
# Select the 0.75–1.50s listening segment before the later speaking actions.
# Frame 16 holds the half-closed-eye expression at ~1.42s shown in the reference.
# Preserve its aspect ratio: scale the square and pad the portrait media canvas.
& ffmpeg -v error -y -ss 0.75 -i assets/videos/assistant/listening_001.mp4 -t 0.75 `
    -an -vf 'fps=24,scale=540:540:flags=lanczos,pad=540:960:0:210:color=black' `
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart `
    assets/videos/assistant/listening_01_attentive.mp4
if ($LASTEXITCODE -ne 0) { throw 'Listening excerpt could not be prepared' }
& "$PSScriptRoot/prepare_navi_matte.ps1" `
    -Source assets/videos/assistant/listening_01_attentive.mp4 `
    -Animation assets/animations/listening_01_attentive.webp `
    -Poster assets/images/listening_01_attentive.png -PosterFrame 16
