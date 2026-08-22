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
const YELLOW: u32 = 0xFF_FF_00;
const OFF: u32 = 0x00_00_00;

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
    max_cpu_percent: f64,
    min_available_ram: u64,
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
            max_cpu_percent: env_number("MAX_CPU_PERCENT", 90.0)?,
            min_available_ram: (env_number::<f64>("MIN_AVAILABLE_RAM_GB", 8.0)? * 1024_f64.powi(3))
                as u64,
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

fn available_ram() -> Result<u64, AnyError> {
    fs::read_to_string("/proc/meminfo")?
        .lines()
        .find_map(|line| {
            line.strip_prefix("MemAvailable:")
                .and_then(|value| value.split_whitespace().next())
                .and_then(|value| value.parse::<u64>().ok())
                .map(|kib| kib * 1024)
        })
        .ok_or_else(|| "MemAvailable not found".into())
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

fn health_alerts(
    config: &Config,
    previous_cpu: CpuTimes,
    current_cpu: CpuTimes,
    ram: u64,
    temperature: Option<f64>,
) -> Vec<String> {
    let mut alerts = Vec::new();
    if temperature.is_some_and(|value| value > config.max_temperature_c) {
        alerts.push(format!("temperature {:.1}C", temperature.unwrap()));
    }
    if ram < config.min_available_ram {
        alerts.push(format!(
            "available RAM {:.1}GiB",
            ram as f64 / 1024_f64.powi(3)
        ));
    }
    let cpu = cpu_percent(previous_cpu, current_cpu);
    if cpu > config.max_cpu_percent {
        alerts.push(format!("CPU {cpu:.1}%"));
    }
    alerts
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

fn set_leds(config: &Config, color: u32) -> Result<(), AnyError> {
    let value = format!("0x{color:06X}");
    let status = Command::new(&config.framework_tool)
        .args(["--rgbkbd", "0"])
        .args(std::iter::repeat_n(&value, config.led_count))
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
    let mut previous_state = String::new();
    let mut previous_cpu = read_cpu_times()?;
    let mut next_health = Instant::now() + config.health;
    let mut alerts = Vec::new();
    let mut warning_phase = false;
    let mut unavailable_phase = false;

    loop {
        if Instant::now() >= next_health {
            next_health = Instant::now() + config.health;
            match (read_cpu_times(), available_ram()) {
                (Ok(current_cpu), Ok(ram)) => {
                    alerts =
                        health_alerts(&config, previous_cpu, current_cpu, ram, max_temperature());
                    previous_cpu = current_cpu;
                }
                (cpu, ram) => eprintln!(
                    "system health check failed: CPU={}, RAM={}",
                    cpu.err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string()),
                    ram.err()
                        .map_or_else(|| "ok".to_owned(), |error| error.to_string())
                ),
            }
        }

        let (color, state, description) = if alerts.is_empty() {
            warning_phase = false;
            match slot_usage(&config) {
                Ok((busy, total)) => {
                    unavailable_phase = false;
                    (
                        utilization_color(busy, total),
                        format!("slots:{busy}/{total}"),
                        format!("llama.cpp slots: {busy}/{total} processing"),
                    )
                }
                Err(error) if router_running(&config.router_user, &config.router_service) => {
                    unavailable_phase = !unavailable_phase;
                    eprintln!("llama.cpp check failed: {error}");
                    (
                        if unavailable_phase { RED } else { OFF },
                        format!("router-unavailable:{unavailable_phase}"),
                        "llama-router active, llama.cpp unavailable".to_owned(),
                    )
                }
                Err(error) => {
                    unavailable_phase = false;
                    eprintln!("llama.cpp check failed: {error}");
                    (
                        OFF,
                        "off".to_owned(),
                        "llama.cpp and router stopped".to_owned(),
                    )
                }
            }
        } else {
            warning_phase = !warning_phase;
            (
                if warning_phase { RED } else { YELLOW },
                format!("health:{warning_phase}:{}", alerts.join(",")),
                format!("system warning: {}", alerts.join(", ")),
            )
        };

        match set_leds(&config, color) {
            Ok(()) => {
                if state != previous_state {
                    eprintln!("{description} -> #{color:06X}");
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

    fn test_config() -> Config {
        Config {
            llamacpp_url: HttpUrl::parse("http://127.0.0.1:8080").unwrap(),
            router_service: "llama-router.service".to_owned(),
            router_user: "olivier".to_owned(),
            framework_tool: "/usr/bin/framework_tool".into(),
            poll: Duration::from_secs(2),
            health: Duration::from_secs(8),
            http_timeout: Duration::from_secs(1),
            max_temperature_c: 90.0,
            max_cpu_percent: 90.0,
            min_available_ram: 8 * 1024_u64.pow(3),
            led_count: 8,
        }
    }

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
    fn warning_thresholds_are_strict() {
        let config = test_config();
        let previous = CpuTimes { idle: 0, total: 0 };
        let at_boundary = CpuTimes {
            idle: 10,
            total: 100,
        };
        assert!(
            health_alerts(
                &config,
                previous,
                at_boundary,
                config.min_available_ram,
                Some(config.max_temperature_c),
            )
            .is_empty()
        );

        let above = CpuTimes {
            idle: 9,
            total: 100,
        };
        let alerts = health_alerts(
            &config,
            previous,
            above,
            config.min_available_ram - 1,
            Some(config.max_temperature_c + 0.1),
        );
        assert_eq!(alerts.len(), 3);
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
