# extract_midi.ps1 - Extract notes from a MIDI file
# Usage: .\extract_midi.ps1 -Path "file.mid"
#
# Parses raw MIDI bytes (Format 0/1), extracts Note-On events,
# and prints note name, octave, and duration in ticks.

param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

$noteNames = @('C','C#','D','D#','E','F','F#','G','G#','A','A#','B')

function Read-VarLen([byte[]]$data, [ref]$pos) {
    $val = 0
    do {
        $b = $data[$pos.Value]
        $pos.Value++
        $val = ($val -shl 7) -bor ($b -band 0x7F)
    } while ($b -band 0x80)
    return $val
}

function Read-UInt16BE([byte[]]$data, [int]$off) {
    return ([uint32]$data[$off] -shl 8) -bor $data[$off+1]
}

function Read-UInt32BE([byte[]]$data, [int]$off) {
    return ([uint32]$data[$off] -shl 24) -bor ([uint32]$data[$off+1] -shl 16) -bor ([uint32]$data[$off+2] -shl 8) -bor $data[$off+3]
}

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))

# Parse header
$headerTag = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
if ($headerTag -ne 'MThd') { Write-Error "Not a MIDI file"; exit 1 }

$headerLen = Read-UInt32BE $bytes 4
$format    = Read-UInt16BE $bytes 8
$numTracks = Read-UInt16BE $bytes 10
$ticksDiv  = Read-UInt16BE $bytes 12

Write-Host "Format: $format  Tracks: $numTracks  Ticks/QN: $ticksDiv"
Write-Host ""

$offset = 8 + $headerLen

for ($t = 0; $t -lt $numTracks; $t++) {
    $trackTag = [System.Text.Encoding]::ASCII.GetString($bytes, $offset, 4)
    $trackLen = Read-UInt32BE $bytes ($offset + 4)
    $offset += 8

    if ($trackTag -ne 'MTrk') {
        Write-Warning "Skipping unknown chunk: $trackTag"
        $offset += $trackLen
        continue
    }

    Write-Host "=== Track $t (length $trackLen bytes) ==="

    $trackEnd = $offset + $trackLen
    $pos = [ref]$offset
    $runningStatus = 0
    $absTick = 0
    $tempo = 500000  # default 120 BPM

    # Collect note-on/off to compute durations
    $activeNotes = @{}  # key = "ch-note" -> [tick, velocity]
    $completedNotes = [System.Collections.ArrayList]::new()

    while ($pos.Value -lt $trackEnd) {
        $delta = Read-VarLen $bytes $pos
        $absTick += $delta

        $statusByte = $bytes[$pos.Value]

        if ($statusByte -band 0x80) {
            $runningStatus = $statusByte
            $pos.Value++
        }
        # else: running status reuse

        $cmd = $runningStatus -band 0xF0
        $ch  = $runningStatus -band 0x0F

        switch ($cmd) {
            0x80 { # Note Off
                $note = $bytes[$pos.Value]; $pos.Value++
                $vel  = $bytes[$pos.Value]; $pos.Value++
                $key = "$ch-$note"
                if ($activeNotes.ContainsKey($key)) {
                    $startTick = $activeNotes[$key][0]
                    $startVel  = $activeNotes[$key][1]
                    $dur = $absTick - $startTick
                    $noteName = $noteNames[$note % 12]
                    $octave = [math]::Floor($note / 12) - 1
                    [void]$completedNotes.Add([PSCustomObject]@{
                        Tick=$startTick; Note="$noteName$octave"; Midi=$note;
                        Vel=$startVel; Dur=$dur; Ch=$ch
                    })
                    $activeNotes.Remove($key)
                }
            }
            0x90 { # Note On
                $note = $bytes[$pos.Value]; $pos.Value++
                $vel  = $bytes[$pos.Value]; $pos.Value++
                $key = "$ch-$note"
                if ($vel -eq 0) {
                    # Note-on with vel 0 = note off
                    if ($activeNotes.ContainsKey($key)) {
                        $startTick = $activeNotes[$key][0]
                        $startVel  = $activeNotes[$key][1]
                        $dur = $absTick - $startTick
                        $noteName = $noteNames[$note % 12]
                        $octave = [math]::Floor($note / 12) - 1
                        [void]$completedNotes.Add([PSCustomObject]@{
                            Tick=$startTick; Note="$noteName$octave"; Midi=$note;
                            Vel=$startVel; Dur=$dur; Ch=$ch
                        })
                        $activeNotes.Remove($key)
                    }
                } else {
                    $activeNotes[$key] = @($absTick, $vel)
                }
            }
            0xA0 { $pos.Value += 2 } # Aftertouch
            0xB0 { $pos.Value += 2 } # Control Change
            0xC0 { $pos.Value += 1 } # Program Change
            0xD0 { $pos.Value += 1 } # Channel Pressure
            0xE0 { $pos.Value += 2 } # Pitch Bend
            0xF0 {
                if ($runningStatus -eq 0xFF) {
                    # Meta event
                    $metaType = $bytes[$pos.Value]; $pos.Value++
                    $metaLen = Read-VarLen $bytes $pos
                    if ($metaType -eq 0x51 -and $metaLen -eq 3) {
                        # Tempo
                        $tempo = ([uint32]$bytes[$pos.Value] -shl 16) -bor ([uint32]$bytes[$pos.Value+1] -shl 8) -bor $bytes[$pos.Value+2]
                        $bpm = [math]::Round(60000000 / $tempo, 1)
                        Write-Host "  Tempo: $tempo us/qn = $bpm BPM"
                    }
                    $pos.Value += $metaLen
                } elseif ($runningStatus -eq 0xF0 -or $runningStatus -eq 0xF7) {
                    # SysEx
                    $sysLen = Read-VarLen $bytes $pos
                    $pos.Value += $sysLen
                } else {
                    # Other system message
                }
            }
        }
    }

    $offset = $trackEnd

    if ($completedNotes.Count -gt 0) {
        $sorted = $completedNotes | Sort-Object Tick

        Write-Host ""
        Write-Host "  Tick  Note   MIDI  Vel  Dur(ticks)  Dur(QN)"
        Write-Host "  ----  ----   ----  ---  ----------  -------"
        foreach ($n in $sorted) {
            $durQN = [math]::Round($n.Dur / $ticksDiv, 3)
            Write-Host ("  {0,5}  {1,-5}  {2,3}  {3,3}  {4,6}      {5}" -f $n.Tick, $n.Note, $n.Midi, $n.Vel, $n.Dur, $durQN)
        }

        # Also output as C array for easy copy-paste
        Write-Host ""
        Write-Host "  /* C note data (period = 100000/freq, dur in delay ticks): */"
        Write-Host "  /* Freq table: C4=262 D4=294 E4=330 F4=349 G4=392 A4=440 B4=494 */"
        Write-Host "  /*             C5=523 D5=587 E5=659 F5=698 G5=784 A5=880 B5=988 */"
        Write-Host ""

        $freqTable = @{
            'C3'=131; 'C#3'=139; 'D3'=147; 'D#3'=156; 'E3'=165; 'F3'=175;
            'F#3'=185; 'G3'=196; 'G#3'=208; 'A3'=220; 'A#3'=233; 'B3'=247;
            'C4'=262; 'C#4'=277; 'D4'=294; 'D#4'=311; 'E4'=330; 'F4'=349;
            'F#4'=370; 'G4'=392; 'G#4'=415; 'A4'=440; 'A#4'=466; 'B4'=494;
            'C5'=523; 'C#5'=554; 'D5'=587; 'D#5'=622; 'E5'=659; 'F5'=698;
            'F#5'=740; 'G5'=784; 'G#5'=831; 'A5'=880; 'A#5'=932; 'B5'=988;
            'C6'=1047; 'C#6'=1109; 'D6'=1175; 'D#6'=1245; 'E6'=1319; 'F6'=1397;
        }

        Write-Host "  static const struct note s_intro[] = {"
        foreach ($n in $sorted) {
            $durQN = $n.Dur / $ticksDiv
            if ($freqTable.ContainsKey($n.Note)) {
                $freq = $freqTable[$n.Note]
                $period = [math]::Round(100000 / $freq)
            } else {
                $period = 0
            }
            # Map duration to a name
            $durName = switch ([math]::Round($durQN * 4)) {
                1  { "T16" }
                2  { "T8" }
                3  { "T8D" }
                4  { "T4" }
                6  { "T4D" }
                8  { "T2" }
                12 { "T2D" }
                16 { "T1" }
                default { "T8 /*$durQN qn*/" }
            }
            $padNote = $n.Note.PadRight(5)
            Write-Host "      {$period, $durName},  /* $padNote dur=$durQN qn */"
        }
        Write-Host "  };"
    }
    Write-Host ""
}
