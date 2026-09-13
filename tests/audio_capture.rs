// SPDX-FileCopyrightText: 2026 vorvek
// SPDX-License-Identifier: GPL-3.0-only

use std::{error::Error, fs, io::Write};

use izarravm_core::{GswMode, VideoCard, MASTER_CLOCK_HZ};
use izarravm_machine::{ExecutionBackend, Machine, MachineProfile, StopReason};

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    izarravm_machine::set_process_execution_backend(ExecutionBackend::Interpreter);
    let mut profile = MachineProfile::gsw_386(16, VideoCard::Vega);
    profile.cpu = match std::env::var("UCDD_TEST_CPU").as_deref().unwrap_or("386") {
        "386" => GswMode::Gsw386,
        "486" => GswMode::Gsw486,
        "586" => GswMode::Gsw586,
        _ => return Err("The test CPU is not valid.".into()),
    };
    profile.wss.enabled = false;
    let mut machine = Machine::new(profile, izarravm_firmware::izarra_bios())?;
    machine.enable_phase_marks();
    if let Some(path) = args.get(3) {
        machine.set_test_snapshot_path(Some(path.into()));
    }
    machine.mount_hdd(fs::read(&args[1])?);
    let mut pcm = Vec::new();
    let mut phase = 0_u64;
    let mut stop = StopReason::CycleLimit { requested: 0 };
    let steps = std::env::var("UCDD_TEST_STEPS").ok().map(|s| s.parse::<u32>()).transpose()?.unwrap_or(30000);
    for _ in 0..steps {
        let before = machine.master_ticks();
        stop = machine.run_until_halt_or_cycles(22000)?;
        phase += (machine.master_ticks() - before) * 49716;
        for (left, right) in machine.render_audio((phase / MASTER_CLOCK_HZ) as usize) {
            pcm.extend(left.to_le_bytes());
            pcm.extend(right.to_le_bytes());
        }
        phase %= MASTER_CLOCK_HZ;
        if !matches!(stop, StopReason::CycleLimit { .. } | StopReason::Halted) {
            break;
        }
    }
    let mut wav = fs::File::create(&args[2])?;
    wav.write_all(b"RIFF")?;
    wav.write_all(&(36 + pcm.len() as u32).to_le_bytes())?;
    wav.write_all(b"WAVEfmt ")?;
    wav.write_all(&16_u32.to_le_bytes())?;
    wav.write_all(&1_u16.to_le_bytes())?;
    wav.write_all(&2_u16.to_le_bytes())?;
    wav.write_all(&44100_u32.to_le_bytes())?;
    wav.write_all(&176400_u32.to_le_bytes())?;
    wav.write_all(&4_u16.to_le_bytes())?;
    wav.write_all(&16_u16.to_le_bytes())?;
    wav.write_all(b"data")?;
    wav.write_all(&(pcm.len() as u32).to_le_bytes())?;
    wav.write_all(&pcm)?;
    let marks: Vec<String> = machine.phase_marks().iter().map(|mark| {
        format!("{{\"id\":{},\"frame\":{}}}", mark.id,
                mark.master_ticks as f64 * 44100.0 / MASTER_CLOCK_HZ as f64)
    }).collect();
    fs::write(std::path::Path::new(&args[2]).with_extension("marks.json"),
              format!("[{}]\n", marks.join(",")))?;
    println!("stop: {stop:?}");
    if std::env::var_os("UCDD_TEST_DISK_EXPORT").is_some() {
        if let Some(disk) = machine.eject_hdd() {
            fs::write(std::path::Path::new(&args[2]).with_extension("disk.img"), disk)?;
        }
    }
    if !matches!(stop, StopReason::TestExit { code: 0 }) {
        for row in 0..25 {
            let text: String = (0..80)
                .map(|col| machine.read_physical_u8(0xb8000 + (row * 80 + col) * 2) as char)
                .collect();
            println!("{text}");
        }
        return Err("The guest test failed.".into());
    }
    Ok(())
}
