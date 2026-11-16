extends RefCounted
## Procedural sound effects: every sound is synthesized into an AudioStreamWAV
## at startup, so the project ships without audio files.
## Usage: const Sfx = preload("res://stories/mars/sfx.gd"); player.stream = Sfx.chime()

const RATE: int = 22050

static var _cache: Dictionary = {}

static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
    var data := PackedByteArray()
    data.resize(samples.size()*2)
    for i in samples.size():
        data.encode_s16(i*2, int(clampf(samples[i],-1.0,1.0)*32767.0))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = RATE
    stream.stereo = false
    stream.data = data
    if loop:
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin = 0
        stream.loop_end = samples.size()
    return stream

static func _buffer(seconds: float) -> PackedFloat32Array:
    var samples := PackedFloat32Array()
    samples.resize(int(seconds*RATE))
    return samples

static func _bell(samples: PackedFloat32Array, start: float, frequency: float, amplitude: float, decay: float) -> void:
    # Additive bell: fundamental plus two quieter partials, exponential decay.
    var first := int(start*RATE)
    for i in range(first, samples.size()):
        var t := float(i-first)/RATE
        var envelope := amplitude*exp(-t*decay)
        if envelope < 0.001:
            break
        samples[i] += envelope*(sin(TAU*frequency*t)+0.35*sin(TAU*frequency*2.0*t)+0.12*sin(TAU*frequency*3.01*t))

static func _cached(key: String, builder: Callable) -> AudioStreamWAV:
    if not _cache.has(key):
        _cache[key] = builder.call()
    return _cache[key]

## Looping wheel motor: low electric hum with a worn "cric-crac" tick.
static func motor_loop() -> AudioStreamWAV:
    return _cached("motor", func() -> AudioStreamWAV:
        var samples := _buffer(2.0)
        var rng := RandomNumberGenerator.new()
        rng.seed = 7
        for i in samples.size():
            var t := float(i)/RATE
            var hum := 0.30*sin(TAU*60.0*t)+0.16*sin(TAU*120.0*t+0.6)+0.08*sin(TAU*180.0*t)
            var whirr := 0.07*sin(TAU*420.0*t)*(0.6+0.4*sin(TAU*8.0*t))
            var tick := 0.0
            for tick_start in [0.0, 0.47, 1.0, 1.53]:
                var dt: float = t-tick_start
                if dt >= 0.0 and dt < 0.05:
                    tick += rng.randf_range(-1.0,1.0)*0.30*exp(-dt*140.0)
            samples[i] = hum+whirr+tick
        return _wav(samples, true))

## Looping Martian wind: soft filtered noise with slow gusts.
static func wind_loop() -> AudioStreamWAV:
    return _cached("wind", func() -> AudioStreamWAV:
        var length := 4*RATE
        var fade := int(0.5*RATE)
        var raw := PackedFloat32Array()
        raw.resize(length+fade)
        var rng := RandomNumberGenerator.new()
        rng.seed = 11
        var low := 0.0
        var lower := 0.0
        for i in raw.size():
            low += 0.045*(rng.randf_range(-1.0,1.0)-low)
            lower += 0.012*(low-lower)
            var t := float(i)/RATE
            raw[i] = (low*2.2+lower*5.0)*(0.75+0.25*sin(TAU*0.25*t))
        var samples := PackedFloat32Array()
        samples.resize(length)
        for i in length:
            # Crossfade the tail into the head so the loop has no click.
            samples[i] = lerpf(raw[length+i], raw[i], float(i)/fade) if i < fade else raw[i]
        return _wav(samples, true))

## Two-note chime for reaching a waypoint.
static func chime() -> AudioStreamWAV:
    return _cached("chime", func() -> AudioStreamWAV:
        var samples := _buffer(1.4)
        _bell(samples, 0.0, 880.0, 0.32, 4.5)
        _bell(samples, 0.13, 1318.5, 0.30, 4.0)
        return _wav(samples))

## Camera shutter for Oppy's photos.
static func shutter() -> AudioStreamWAV:
    return _cached("shutter", func() -> AudioStreamWAV:
        var samples := _buffer(0.28)
        var rng := RandomNumberGenerator.new()
        rng.seed = 23
        for i in samples.size():
            var t := float(i)/RATE
            var click := rng.randf_range(-1.0,1.0)*0.5*exp(-t*90.0)
            if t > 0.10:
                click += rng.randf_range(-1.0,1.0)*0.35*exp(-(t-0.10)*110.0)
            samples[i] = click+0.12*sin(TAU*2100.0*t)*exp(-t*60.0)
        return _wav(samples))

## Oppy's little three-tone voice chirp.
static func chirp() -> AudioStreamWAV:
    return _cached("chirp", func() -> AudioStreamWAV:
        var samples := _buffer(0.30)
        var notes := [920.0, 1230.0, 1560.0]
        for n in notes.size():
            var first := int(n*0.09*RATE)
            var count := int(0.075*RATE)
            for i in count:
                var x := float(i)/count
                samples[first+i] += 0.26*sin(PI*x)*sin(TAU*notes[n]*float(i)/RATE)
        return _wav(samples))

## Soft low tone that opens a narrator line.
static func narrator_tone() -> AudioStreamWAV:
    return _cached("narrator", func() -> AudioStreamWAV:
        var samples := _buffer(0.6)
        _bell(samples, 0.0, 220.0, 0.16, 6.0)
        return _wav(samples))

## Descending sweep for the rover powering down.
static func power_down() -> AudioStreamWAV:
    return _cached("power_down", func() -> AudioStreamWAV:
        var samples := _buffer(2.2)
        var phase := 0.0
        for i in samples.size():
            var x := float(i)/samples.size()
            phase += TAU*lerpf(520.0, 60.0, pow(x,0.6))/RATE
            samples[i] = (1.0-x)*0.30*(sin(phase)+0.3*sin(phase*2.0))
        return _wav(samples))

## Slow music-box lullaby for the epilogue.
static func lullaby() -> AudioStreamWAV:
    return _cached("lullaby", func() -> AudioStreamWAV:
        var a := 440.0
        # A major pentatonic, rising then settling home.
        var semitones := [12, 16, 19, 24, 21, 19, 16, 19, 12, 16, 9, 12, 7, 9, 4, 0]
        var beat := 0.62
        var samples := _buffer(semitones.size()*beat+3.0)
        for n in semitones.size():
            _bell(samples, n*beat, a*pow(2.0, semitones[n]/12.0), 0.20, 2.4)
            if n % 4 == 0:
                _bell(samples, n*beat, a*pow(2.0, (semitones[n]-12)/12.0), 0.10, 1.6)
        return _wav(samples))
