// SPDX-FileCopyrightText: 2026 vorvek
// SPDX-License-Identifier: GPL-3.0-only

use std::{error::Error, fs, io::Write};

use izarravm_core::{GswMode, VideoCard, MASTER_CLOCK_HZ};
use izarravm_machine::{ExecutionBackend, Machine, MachineProfile, StopReason};

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    izarravm_machine::set_process_execution_backend(ExecutionBackend::Interpreter);
    let memory_mib = std::env::var("UCDD_TEST_MEMORY_MIB").ok()
        .map(|value| value.parse()).transpose()?.unwrap_or(16);
    let mut profile = MachineProfile::gsw_386(memory_mib, VideoCard::Vega);
    profile.cpu = match std::env::var("UCDD_TEST_CPU").as_deref().unwrap_or("386") {
        "386" => GswMode::Gsw386,
        "486" => GswMode::Gsw486,
        "586" => GswMode::Gsw586,
        _ => return Err("The test CPU is not valid.".into()),
    };
    profile.wss.enabled = false;
    if std::env::var("UCDD_TEST_OUTPUT").as_deref() == Ok("wss") {
        profile.wss.enabled = true;
        profile.sound_blaster.enabled = false;
    }
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
    let keys: Vec<(u32, u8)> = std::env::var("UCDD_TEST_KEYS").unwrap_or_default()
        .split(',').filter(|entry| !entry.is_empty()).map(|entry| {
            let (step, code) = entry.split_once(':').ok_or("The key event is not valid.")?;
            Ok((step.parse()?, u8::from_str_radix(code, 16)?))
        }).collect::<Result<_, Box<dyn Error>>>()?;
    let live = std::env::var_os("UCDD_TEST_LIVE").map(std::path::PathBuf::from);
    for step in 0..steps {
        if step % 1000 == 0
            && let Some(directory) = &live
        {
            let input = directory.join("input.txt");
            if input.exists() {
                let commands = fs::read_to_string(&input)?;
                fs::remove_file(input)?;
                for line in commands.lines() {
                    let fields: Vec<_> = line.split_whitespace().collect();
                    match fields.as_slice() {
                        ["key", codes @ ..] => {
                            let codes = codes.iter().map(|code| u8::from_str_radix(code, 16))
                                .collect::<Result<Vec<_>, _>>()?;
                            machine.inject_key_scancodes(&codes);
                        }
                        ["mouse", dx, dy, buttons] => {
                            machine.inject_mouse(dx.parse()?, dy.parse()?, buttons.parse()?);
                        }
                        _ => return Err("The input command is not valid.".into()),
                    }
                }
            }
            let (pixels, width, height) = machine.capture_frame_argb();
            let mut frame = format!("P6\n{width} {height}\n255\n").into_bytes();
            for pixel in pixels {
                frame.extend([(pixel >> 16) as u8, (pixel >> 8) as u8, pixel as u8]);
            }
            fs::write(directory.join("frame.ppm"), frame)?;
            fs::write(directory.join("step.txt"), step.to_string())?;
        }
        for &(_, code) in keys.iter().filter(|&&(at, _)| at == step) {
            machine.inject_key_scancodes(&[code]);
        }
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
    if let Some(path) = std::env::var_os("UCDD_TEST_FRAME") {
        let (pixels, width, height) = machine.capture_frame_argb();
        let mut frame = fs::File::create(path)?;
        write!(frame, "P6\n{width} {height}\n255\n")?;
        for pixel in pixels {
            frame.write_all(&[(pixel >> 16) as u8, (pixel >> 8) as u8, pixel as u8])?;
        }
        println!("display: {:?}", machine.distira_scanout_state());
    }
    if let Some(path) = std::env::var_os("UCDD_TEST_MEMORY_DUMP") {
        let bytes = std::env::var("UCDD_TEST_MEMORY_BYTES").ok()
            .map(|value| value.parse::<u32>()).transpose()?.unwrap_or(0x200000);
        let memory: Vec<u8> = (0..bytes).map(|address| machine.read_physical_u8(address)).collect();
        fs::write(path, memory)?;
    }
    if std::env::var_os("UCDD_TEST_DISK_EXPORT").is_some() {
        if let Some(disk) = machine.eject_hdd() {
            fs::write(std::path::Path::new(&args[2]).with_extension("disk.img"), disk)?;
        }
    }
    if !matches!(stop, StopReason::TestExit { code: 0 }) {
        println!("registers: {:?}", machine.cpu().registers);
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
