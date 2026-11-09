"""Compile ONLY the shipped trusted UnoBlink fixture using external AVR tools/core.
No download or global config. Not an in-game compiler for untrusted player code.
Usage: python build_arduino_fixture.py TOOLCHAIN_AVR_DIR ARDUINO_CORE_DIR OUTPUT_DIR
"""
import pathlib
import subprocess
import sys

tool, platform, output = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:4])
output.mkdir(parents=True, exist_ok=True)
core = platform / 'cores' / 'arduino'
includes = ['-I' + str(core), '-I' + str(platform / 'variants' / 'standard')]
common = ['-mmcu=atmega328p', '-DF_CPU=16000000L', '-DARDUINO=10819',
          '-DARDUINO_AVR_UNO', '-DARDUINO_ARCH_AVR', '-Os', '-ffunction-sections', '-fdata-sections']
objects = []
for source in sorted(core.iterdir()):
    if source.suffix not in ('.c', '.cpp', '.S'):
        continue
    compiler = 'avr-g++' if source.suffix == '.cpp' else 'avr-gcc'
    obj = output / (source.name + '.o')
    flags = ['-std=gnu++11', '-fno-exceptions', '-fno-threadsafe-statics'] if source.suffix == '.cpp' else []
    subprocess.run([str(tool / 'bin' / (compiler + '.exe')), *common, *flags,
                    *includes, '-c', str(source), '-o', str(obj)], check=True)
    objects.append(str(obj))
fixture = pathlib.Path(__file__).resolve().parents[3] / 'assets' / 'workers' / 'firmware' / 'UnoBlink.ino'
sketch = output / 'sketch.cpp'
sketch.write_text('#include <Arduino.h>\n' + fixture.read_text(), encoding='utf-8')
sketch_obj = output / 'sketch.o'
subprocess.run([str(tool / 'bin' / 'avr-g++.exe'), *common, *includes,
                '-std=gnu++11', '-fno-exceptions', '-c', str(sketch), '-o', str(sketch_obj)], check=True)
elf = output / 'blink.elf'
subprocess.run([str(tool / 'bin' / 'avr-gcc.exe'), '-mmcu=atmega328p', '-Wl,--gc-sections',
                '-o', str(elf), str(sketch_obj), *objects, '-lm'], check=True)
subprocess.run([str(tool / 'bin' / 'avr-objcopy.exe'), '-O', 'ihex', '-R', '.eeprom',
                str(elf), str(output / 'blink.hex')], check=True)
print('COMPILED', output / 'blink.hex')
