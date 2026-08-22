use serde::Deserialize;
use std::env;
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

type AnyError = Box<dyn Error + Send + Sync>;

const WHITE: u32 = 0xFF_FF_FF;
const RED: u32 = 0xFF_00_00;
const OFF: u32 = 0x00_00_00;
const TOP_LEFT: usize = 0;
const TOP_RIGHT: usize = 3;
const BOTTOM_LEFT: usize = 4;
const BOTTOM_RIGHT: usize = 7;

#[derive(Debug)]
struct Config {
    llamacpp_url: HttpUrl,
    router_service: String,
    router_user: String,
    framework_tool: PathBuf,
    poll: Duration,
    health: Duration,
    http_timeout: Duration,
    max_temperature_c: f64,
    max_power_watts: f64,
    max_disk_mbps: f64,
    max_network_mbps: f64,
    led_count: usize,
}

impl Config {
    fn from_env() -> Result<Self, AnyError> {
        Ok(Self {
            llamacpp_url: HttpUrl::parse(&env_string("LLAMACPP_URL", "http://127.0.0.1:8080"))?,
            router_service: env_string("ROUTER_SERVICE", "llama-router.service"),
            router_user: env_string("ROUTER_USER", "olivier"),
            framework_tool: env_string("FRAMEWORK_TOOL", "/usr/bin/framework_tool").into(),
            poll: Duration::from_secs_f64(env_number("POLL_SECONDS", 2.0)?),
            health: Duration::from_secs_f64(env_number("HEALTH_SECONDS", 8.0)?),
            http_timeout: Duration::from_secs_f64(env_number("HTTP_TIMEOUT", 1.5)?),
            max_temperature_c: env_number("MAX_TEMPERATURE_C", 90.0)?,
            max_power_watts: env_number("MAX_POWER_WATTS", 120.0)?,
            max_disk_mbps: env_number("MAX_DISK_MBPS", 1000.0)?,
            max_network_mbps: env_number("MAX_NETWORK_MBPS", 1000.0)?,
            led_count: env_number("LED_COUNT", 8)?,
        })
    }
}

fn env_string(name: &str, default: &str) -> String {
    env::var(name).unwrap_or_else(|_| default.to_owned())
}

fn env_number<T>(name: &str, default: T) -> Result<T, AnyError>
where
    T: std::str::FromStr,
    T::Err: Error + Send + Sync + 'static,
{
    match env::var(name) {
        Ok(value) => Ok(value.parse()?),
        Err(_) => Ok(default),
    }
}

#[derive(Debug)]
struct HttpUrl {
    host: String,
    port: u16,
    base_path: String,
}

impl HttpUrl {
    fn parse(value: &str) -> Result<Self, AnyError> {
        let authority_and_path = value
            .strip_prefix("http://")
            .ok_or("LLAMACPP_URL must use http://")?;
        let (authority, path) = authority_and_path
            .split_once('/')
            .map_or((authority_and_path, ""), |(authority, path)| {
                (authority, path)
            });
        let (host, port) = authority
            .rsplit_once(':')
            .map_or((authority, 80), |(host, port)| {
                (host, port.parse().unwrap_or(0))
            });
        if host.is_empty() || port == 0 {
            return Err("LLAMACPP_URL has an invalid host or port".into());
        }
        Ok(Self {
            host: host.to_owned(),
            port,
            base_path: if path.is_empty() {
                String::new()
            } else {
                format!("/{path}").trim_end_matches('/').to_owned()
            },
        })
    }

    fn get(&self, path: &str, timeout: Duration) -> Result<Vec<u8>, AnyError> {
        let address = format!("{}:{}", self.host, self.port)
            .to_socket_addrs()?
            .next()
            .ok_or("could not resolve llama.cpp address")?;
        let mut stream = TcpStream::connect_timeout(&address, timeout)?;
        stream.set_read_timeout(Some(timeout))?;
        stream.set_write_timeout(Some(timeout))?;
        let target = format!("{}{}", self.base_path, path);
        write!(
            stream,
            "GET {target} HTTP/1.0\r\nHost: {}:{}\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
            self.host, self.port
        )?;
        let mut response = Vec::new();
        stream.read_to_end(&mut response)?;
        let header_end = response
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
            .ok_or("malformed HTTP response")?;
        let headers = std::str::from_utf8(&response[..header_end])?;
        let status = headers
            .lines()
            .next()
            .and_then(|line| line.split_whitespace().nth(1))
            .and_then(|code| code.parse::<u16>().ok())
            .ok_or("malformed HTTP status")?;
        if !(200..300).contains(&status) {
            return Err(format!("llama.cpp returned HTTP {status}").into());
        }
        let body = &response[header_end + 4..];
        if headers.lines().any(|line| {
            line.eq_ignore_ascii_case("transfer-encoding: chunked")
                || line
                    .to_ascii_lowercase()
                    .starts_with("transfer-encoding: chunked")
        }) {
            decode_chunked(body)
        } else {
            Ok(body.to_vec())
        }
    }

    fn get_json<T: for<'de> Deserialize<'de>>(
        &self,
        path: &str,
        timeout: Duration,
    ) -> Result<T, AnyError> {
        Ok(serde_json::from_slice(&self.get(path, timeout)?)?)
    }
}

fn decode_chunked(mut input: &[u8]) -> Result<Vec<u8>, AnyError> {
    let mut output = Vec::new();
    loop {
        let line_end = input
            .windows(2)
            .position(|window| window == b"\r\n")
            .ok_or("malformed HTTP chunk size")?;
        let size_text = std::str::from_utf8(&input[..line_end])?
            .split(';')
            .next()
            .ok_or("missing HTTP chunk size")?;
        let size = usize::from_str_radix(size_text.trim(), 16)?;
        input = &input[line_end + 2..];
        if size == 0 {
            return Ok(output);
        }
        if input.len() < size + 2 || &input[size..size + 2] != b"\r\n" {
            return Err("truncated HTTP chunk".into());
        }
        output.extend_from_slice(&input[..size]);
        input = &input[size + 2..];
    }
}

#[derive(Deserialize)]
struct ModelsResponse {
    data: Vec<Model>,
}

#[derive(Deserialize)]
struct Model {
    id: String,
    status: ModelStatus,
}

#[derive(Deserialize)]
struct ModelStatus {
    value: String,
}

#[derive(Deserialize)]
struct Slot {
    is_processing: bool,
}

fn count_slots(slots: &[Slot]) -> (usize, usize) {
    (
        slots.iter().filter(|slot| slot.is_processing).count(),
        slots.len(),
    )
}

fn running_models(response: ModelsResponse) -> Vec<String> {
    response
        .data
        .into_iter()
        .filter(|model| matches!(model.status.value.as_str(), "loaded" | "running"))
        .map(|model| model.id)
        .collect()
}

fn percent_encode(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            encoded.push(char::from(byte));
        } else {
            write!(encoded, "%{byte:02X}").expect("writing to String cannot fail");
        }
    }
    encoded
}

fn slot_usage(config: &Config) -> Result<(usize, usize), AnyError> {
    let models: ModelsResponse = config
        .llamacpp_url
        .get_json("/v1/models", config.http_timeout)?;
    let mut busy = 0;
    let mut total = 0;
    for model in running_models(models) {
        let path = format!("/slots?model={}&autoload=false", percent_encode(&model));
        let slots: Vec<Slot> = config.llamacpp_url.get_json(&path, config.http_timeout)?;
        let (model_busy, model_total) = count_slots(&slots);
        busy += model_busy;
        total += model_total;
    }
    Ok((busy, total))
}

#[derive(Clone, Copy)]
struct CpuTimes {
    idle: u64,
    total: u64,
}

fn read_cpu_times() -> Result<CpuTimes, AnyError> {
    let stat = fs::read_to_string("/proc/stat")?;
    let values: Vec<u64> = stat
        .lines()
        .next()
        .ok_or("missing aggregate CPU counters")?
        .split_whitespace()
        .skip(1)
        .map(str::parse)
        .collect::<Result<_, _>>()?;
    if values.len() < 4 {
        return Err("incomplete aggregate CPU counters".into());
    }
    Ok(CpuTimes {
        idle: values[3] + values.get(4).copied().unwrap_or(0),
        total: values.iter().sum(),
    })
}

fn cpu_percent(previous: CpuTimes, current: CpuTimes) -> f64 {
    let total = current.total.saturating_sub(previous.total);
    let idle = current.idle.saturating_sub(previous.idle);
    if total == 0 {
        0.0
    } else {
        100.0 * (1.0 - idle as f64 / total as f64)
    }
}

fn memory_used_fraction() -> Result<f64, AnyError> {
    let meminfo = fs::read_to_string("/proc/meminfo")?;
    let read_kib = |key: &str| {
        meminfo.lines().find_map(|line| {
            line.strip_prefix(key)
                .and_then(|value| value.split_whitespace().next())
                .and_then(|value| value.parse::<u64>().ok())
        })
    };
    let total = read_kib("MemTotal:").ok_or("MemTotal not found")?;
    let available = read_kib("MemAvailable:").ok_or("MemAvailable not found")?;
    Ok(1.0 - available.min(total) as f64 / total as f64)
}

fn gpu_usage_fraction() -> Option<f64> {
    fs::read_dir("/sys/class/drm")
        .ok()?
        .flatten()
        .filter(|entry| {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            name.strip_prefix("card")
                .is_some_and(|suffix| suffix.chars().all(|character| character.is_ascii_digit()))
        })
        .filter_map(|entry| fs::read_to_string(entry.path().join("device/gpu_busy_percent")).ok())
        .filter_map(|value| value.trim().parse::<f64>().ok())
        .map(|percent| percent / 100.0)
        .reduce(f64::max)
}

fn power_watts() -> Option<f64> {
    fs::read_dir("/sys/class/hwmon")
        .ok()?
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            ["power1_average", "power1_input"]
                .into_iter()
                .find_map(|name| fs::read_to_string(path.join(name)).ok())
        })
        .filter_map(|value| value.trim().parse::<f64>().ok())
        .map(|microwatts| microwatts / 1_000_000.0)
        .reduce(f64::max)
}

fn is_whole_disk(name: &str) -> bool {
    (name.starts_with("nvme") && !name.contains('p'))
        || ((name.starts_with("sd") || name.starts_with("vd"))
            && !name.chars().any(|character| character.is_ascii_digit()))
}

fn disk_bytes() -> Result<u64, AnyError> {
    let mut sectors = 0_u64;
    for line in fs::read_to_string("/proc/diskstats")?.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() >= 10 && is_whole_disk(fields[2]) {
            sectors += fields[5].parse::<u64>()? + fields[9].parse::<u64>()?;
        }
    }
    Ok(sectors * 512)
}

fn network_bytes() -> Result<u64, AnyError> {
    let mut bytes = 0_u64;
    for line in fs::read_to_string("/proc/net/dev")?.lines().skip(2) {
        let Some((interface, counters)) = line.split_once(':') else {
            continue;
        };
        if interface.trim() == "lo" {
            continue;
        }
        let fields: Vec<&str> = counters.split_whitespace().collect();
        if fields.len() >= 9 {
            bytes += fields[0].parse::<u64>()? + fields[8].parse::<u64>()?;
        }
    }
    Ok(bytes)
}

fn collect_temperatures(path: &Path, output: &mut Vec<f64>) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if ((name.starts_with("temp") && name.ends_with("_input")) || name == "temp")
            && let Ok(value) = fs::read_to_string(path)
            && let Ok(value) = value.trim().parse::<f64>()
        {
            output.push(if value > 1000.0 {
                value / 1000.0
            } else {
                value
            });
        }
    }
}

fn max_temperature() -> Option<f64> {
    let mut values = Vec::new();
    for class in ["/sys/class/hwmon", "/sys/class/thermal"] {
        if let Ok(entries) = fs::read_dir(class) {
            for entry in entries.flatten() {
                collect_temperatures(&entry.path(), &mut values);
            }
        }
    }
    values.into_iter().reduce(f64::max)
}

fn lerp_channel(start: u32, end: u32, fraction: f64) -> u32 {
    (start as f64 + (end as f64 - start as f64) * fraction).round() as u32
}

fn lerp_color(start: u32, end: u32, fraction: f64) -> u32 {
    let fraction = fraction.clamp(0.0, 1.0);
    let red = lerp_channel((start >> 16) & 0xFF, (end >> 16) & 0xFF, fraction);
    let green = lerp_channel((start >> 8) & 0xFF, (end >> 8) & 0xFF, fraction);
    let blue = lerp_channel(start & 0xFF, end & 0xFF, fraction);
    (red << 16) | (green << 8) | blue
}

fn resource_color(fraction: f64) -> u32 {
    const STOPS: [u32; 4] = [0x66_CC_FF, 0x00_FF_00, 0xFF_FF_00, RED];
    let position = fraction.clamp(0.0, 1.0) * (STOPS.len() - 1) as f64;
    let segment = (position.floor() as usize).min(STOPS.len() - 2);
    lerp_color(
        STOPS[segment],
        STOPS[segment + 1],
        position - segment as f64,
    )
}

fn utilization_color(busy: usize, total: usize) -> u32 {
    if busy == 0 || total == 0 {
        return WHITE;
    }
    let fraction = (busy as f64 / total as f64).min(1.0);
    let green_blue = (255.0 * (1.0 - fraction)).round() as u32;
    (0xFF << 16) | (green_blue << 8) | green_blue
}

fn router_running(user: &str, service: &str) -> bool {
    Command::new("systemctl")
        .args([
            "--user",
            &format!("--machine={user}@.host"),
            "status",
            service,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}

fn set_leds(config: &Config, colors: &[u32]) -> Result<(), AnyError> {
    let values: Vec<String> = colors
        .iter()
        .map(|color| format!("0x{color:06X}"))
        .collect();
    let status = Command::new(&config.framework_tool)
        .args(["--rgbkbd", "0"])
        .args(&values)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("framework_tool exited with {status}").into())
    }
}

fn run() -> Result<(), AnyError> {
    let config = Config::from_env()?;
    if config.led_count <= BOTTOM_RIGHT {
        return Err("LED_COUNT must be at least 8 for four-corner mode".into());
    }
    let mut previous_state = String::new();
    let mut previous_cpu = read_cpu_times()?;
    let mut previous_disk_bytes = disk_bytes()?;
    let mut previous_network_bytes = network_bytes()?;
    let mut previous_sample = Instant::now();
    let mut next_health = Instant::now() + config.health;
    let mut cpu_usage = 0.0;
    let mut gpu_usage = gpu_usage_fraction().unwrap_or(0.0);
    let mut power = power_watts().unwrap_or(0.0);
    let mut ram_usage = memory_used_fraction()?;
    let mut disk_usage = 0.0;
    let mut network_usage = 0.0;
    let mut temperature = max_temperature().unwrap_or(0.0);
    let mut unavailable_phase = false;

    loop {
        if Instant::now() >= next_health {
            next_health = Instant::now() + config.health;
            match (
                read_cpu_times(),
                memory_used_fraction(),
                disk_bytes(),
                network_bytes(),
            ) {
                (Ok(current_cpu), Ok(ram), Ok(current_disk), Ok(current_network)) => {
                    let elapsed = previous_sample.elapsed().as_secs_f64().max(0.001);
                    cpu_usage = cpu_percent(previous_cpu, current_cpu);
                    gpu_usage = gpu_usage_fraction().unwrap_or(gpu_usage);
                    power = power_watts().unwrap_or(power);
                    ram_usage = ram;
                    disk_usage = current_disk.saturating_sub(previous_disk_bytes) as f64
                        / elapsed
                        / (config.max_disk_mbps * 1_000_000.0);
                    network_usage = current_network.saturating_sub(previous_network_bytes) as f64
                        * 8.0
                        / elapsed
                        / (config.max_network_mbps * 1_000_000.0);
                    temperature = max_temperature().unwrap_or(temperature);
                    previous_cpu = current_cpu;
                    previous_disk_bytes = current_disk;
                    previous_network_bytes = current_network;
                    previous_sample = Instant::now();
                }
                (cpu, ram, disk, network) => eprintln!(
                    "system metrics failed: CPU={}, RAM={}, disk={}, network={}",
                    cpu.err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string()),
                    ram.err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string()),
                    disk.err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string()),
                    network
                        .err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string())
                ),
            }
        }

        let (llama_color, llama_state) = match slot_usage(&config) {
            Ok((busy, total)) => {
                unavailable_phase = false;
                (
                    utilization_color(busy, total),
                    format!("llama.cpp {busy}/{total} slots"),
                )
            }
            Err(error) if router_running(&config.router_user, &config.router_service) => {
                unavailable_phase = !unavailable_phase;
                eprintln!("llama.cpp check failed: {error}");
                (
                    if unavailable_phase { RED } else { OFF },
                    "llama-router active, endpoint unavailable".to_owned(),
                )
            }
            Err(error) => {
                unavailable_phase = false;
                eprintln!("llama.cpp check failed: {error}");
                (OFF, "llama.cpp stopped".to_owned())
            }
        };

        let temperature_fraction =
            ((temperature - 30.0) / (config.max_temperature_c - 30.0)).clamp(0.0, 1.0);
        let mut colors = vec![OFF; config.led_count];
        colors[TOP_LEFT] = resource_color(temperature_fraction);
        colors[1] = resource_color(gpu_usage);
        colors[2] = resource_color(cpu_usage / 100.0);
        colors[TOP_RIGHT] = resource_color(power / config.max_power_watts);
        colors[BOTTOM_LEFT] = resource_color(ram_usage);
        colors[5] = resource_color(disk_usage);
        colors[6] = resource_color(network_usage);
        colors[BOTTOM_RIGHT] = llama_color;
        let state = format!(
            "temp:{temperature:.1}:gpu:{gpu_usage:.3}:cpu:{cpu_usage:.1}:power:{power:.1}:ram:{ram_usage:.3}:disk:{disk_usage:.3}:network:{network_usage:.3}:{llama_state}"
        );

        match set_leds(&config, &colors) {
            Ok(()) => {
                if state != previous_state {
                    eprintln!(
                        "temperature {temperature:.1}C, GPU {:.1}%, CPU {cpu_usage:.1}%, power {power:.1}W, RAM {:.1}%, disk {:.1}%, network {:.1}%, {llama_state}",
                        gpu_usage * 100.0,
                        ram_usage * 100.0,
                        disk_usage.clamp(0.0, 1.0) * 100.0,
                        network_usage.clamp(0.0, 1.0) * 100.0,
                    );
                    previous_state = state;
                }
            }
            Err(error) => eprintln!("could not set Framework RGB LEDs: {error}"),
        }
        thread::sleep(config.poll);
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("framework-rgb failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_capacity_to_white_pink_and_red() {
        assert_eq!(utilization_color(0, 4), WHITE);
        assert_eq!(utilization_color(2, 4), 0xFF_80_80);
        assert_eq!(utilization_color(4, 4), RED);
    }

    #[test]
    fn calculates_aggregate_cpu_delta() {
        let previous = CpuTimes {
            idle: 100,
            total: 200,
        };
        let current = CpuTimes {
            idle: 110,
            total: 300,
        };
        assert_eq!(cpu_percent(previous, current), 90.0);
    }

    #[test]
    fn filters_running_models() {
        let response: ModelsResponse = serde_json::from_str(
            r#"{"data":[{"id":"loaded","status":{"value":"loaded"}},{"id":"running","status":{"value":"running"}},{"id":"cold","status":{"value":"unloaded"}}]}"#,
        )
        .unwrap();
        assert_eq!(running_models(response), ["loaded", "running"]);
    }

    #[test]
    fn aggregates_processing_slots() {
        let slots: Vec<Slot> = serde_json::from_str(
            r#"[{"is_processing":true},{"is_processing":false},{"is_processing":true}]"#,
        )
        .unwrap();
        assert_eq!(count_slots(&slots), (2, 3));
    }

    #[test]
    fn resource_palette_has_expected_stops() {
        assert_eq!(resource_color(0.0), 0x66_CC_FF);
        assert_eq!(resource_color(1.0 / 3.0), 0x00_FF_00);
        assert_eq!(resource_color(2.0 / 3.0), 0xFF_FF_00);
        assert_eq!(resource_color(1.0), RED);
    }

    #[test]
    fn percent_encodes_model_ids() {
        assert_eq!(percent_encode("model name/a"), "model%20name%2Fa");
    }

    #[test]
    fn decodes_chunked_http_body() {
        assert_eq!(
            decode_chunked(b"3\r\n[1,\r\n3\r\n2]\n\r\n0\r\n\r\n").unwrap(),
            b"[1,2]\n"
        );
    }
}
