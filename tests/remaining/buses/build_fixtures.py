from pathlib import Path
import subprocess,sys
# Only this fixed, shipped trusted fixture is compiled. Not a player-source compiler.
tool=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
source=Path(__file__).with_name('avr_bus_fixture.c')
for kind,name in [(1,'eeprom'),(2,'i2c'),(3,'uart'),(4,'uart-sender'),(5,'uart-receiver'),(6,'i2c-reader')]:
 elf=out/(name+'.elf');hexfile=out/(name+'.hex')
 subprocess.run([str(tool/'avr-gcc.exe'),'-mmcu=atmega328p','-DF_CPU=16000000UL','-DTEST_KIND='+str(kind),'-Os','-o',str(elf),str(source)],check=True)
 subprocess.run([str(tool/'avr-objcopy.exe'),'-O','ihex','-R','.eeprom',str(elf),str(hexfile)],check=True)
 print('COMPILED trusted fixture',name)
