"""Read Linux counters without extra packages; emit one sample every two seconds."""
import json
from pathlib import Path
import time


def snapshot():
    # guest/guest_nice are already included in user/nice.
    cpu = list(map(int, Path('/proc/stat').read_text().splitlines()[0].split()[1:9]))
    memory = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        memory[key] = int(value.split()[0])
    disks = {}
    for line in Path('/proc/diskstats').read_text().splitlines():
        fields = line.split()
        name = fields[2]
        # Whole physical devices only: avoid counting partitions and dm twice.
        if (Path('/sys/block') / name / 'device').exists():
            disks[name] = (int(fields[5]) * 512, int(fields[9]) * 512)
    temperatures = []
    for hwmon in Path('/sys/class/hwmon').glob('hwmon*'):
        try:
            if (hwmon / 'name').read_text().strip() not in ('k10temp', 'coretemp', 'zenpower'):
                continue
            for sensor in hwmon.glob('temp*_input'):
                temperatures.append(int(sensor.read_text()) / 1000)
        except (OSError, ValueError):
            continue
    return time.monotonic(), sum(cpu), cpu[3] + cpu[4], memory, disks, max(temperatures, default=None)


def metrics(previous, current):
    now, total, idle, memory, disks, temperature = current
    elapsed = now - previous[0]
    ticks = total - previous[1]
    read = sum(max(0, values[0] - previous[4][name][0]) for name, values in disks.items() if name in previous[4]) / elapsed
    write = sum(max(0, values[1] - previous[4][name][1]) for name, values in disks.items() if name in previous[4]) / elapsed
    gpu_loads = []
    for sensor in Path('/sys/class/drm').glob('card*/device/gpu_busy_percent'):
        try:
            gpu_loads.append(max(0, min(100, int(sensor.read_text()))))
        except (OSError, ValueError):
            continue
    return {
        'gpu': max(gpu_loads, default=None),
        'cpu': max(0, min(100, 100 * (1 - (idle - previous[2]) / ticks))) if ticks else 0,
        'memory': 100 * (1 - memory['MemAvailable'] / memory['MemTotal']),
        'usedGiB': (memory['MemTotal'] - memory['MemAvailable']) / 1048576,
        'totalGiB': memory['MemTotal'] / 1048576,
        'read': read / 1048576, 'write': write / 1048576,
        'temperature': temperature,
    }


if __name__ == '__main__':
    previous = snapshot()
    while True:
        time.sleep(2)
        current = snapshot()
        print(json.dumps(metrics(previous, current)), flush=True)
        previous = current
