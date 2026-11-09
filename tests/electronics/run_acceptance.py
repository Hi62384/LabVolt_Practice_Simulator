"""Run from this project with Python 3; optional GODOT environment variable."""
from pathlib import Path
import os, subprocess, tempfile, time, sys
project=Path(__file__).resolve().parents[2]
godot=os.environ.get('GODOT',str(project/'runtime'/'Godot_v4.5.1-stable_win64_console.exe'))
logs=Path(tempfile.mkdtemp(prefix='labvolt-validation-'))
names=['dc','integrated','custom','world','trade','editor','devices','inputs','analyzer','firmware','ide','meter_modes','pcb','nested_firmware','stateful','board_movement','assortments','designer','board_hotbar','standalone','ic_surface','bjt','shared_input','shift_register','notebook','edit_copy','coupling','coupling_world','pcb_coupling','ac_bridge','recursive_surface','ac_world','component_meshes','audio_output','speaker','speaker_audio','opamp','ac_passive','transformer_transient','ac_wattmeter','ac_daq','daq_phasor','package64_core','io_input_guard','integrated_io','integrated_eeprom','public_device_state']
failed=[]
for name in names:
 env=os.environ.copy();env['APPDATA']=str(logs/name)
 command=[godot,*([] if name in ['ide','audio_output','speaker_audio','opamp','ac_passive','transformer_transient','ac_wattmeter','ac_daq','daq_phasor','package64_core','io_input_guard','integrated_io','integrated_eeprom','public_device_state'] else ['--headless']),'--path',str(project),'--script',str(Path(__file__).parent/f'test_{name}.gd')]
 try:
  result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',env=env,timeout=60)
  output=result.stdout+result.stderr
  ok=result.returncode==0 and 'PASS' in output and 'SCRIPT ERROR' not in output and 'FAIL ' not in output
 except subprocess.TimeoutExpired as error:
  output='TIMEOUT\n'+str(error.stdout)+str(error.stderr);ok=False
 (logs/(name+'.log')).write_text(output,encoding='utf-8')
 print(name,'PASS' if ok else 'FAIL',flush=True)
 if not ok:failed.append(name)
for name,roles in [('dc_network',['host','clientA','clientB']),('pcb_network',['host','client']),('coupling_network',['host','clientA','clientB']),('integrated_io_network',['host','client'])]:
 running=[]
 for role in roles:
  env=os.environ.copy();env['APPDATA']=str(logs/(name+'_'+role))
  path=logs/(name+'_'+role+'.log');handle=path.open('w',encoding='utf-8')
  proc=subprocess.Popen([godot,'--headless','--path',str(project),'--script',str(Path(__file__).parent/f'test_{name}.gd'),'--',role],env=env,stdout=handle,stderr=subprocess.STDOUT)
  running.append((role,proc,handle,path));time.sleep(2)
 for role,proc,handle,path in running:
  try:code=proc.wait(timeout=70)
  except subprocess.TimeoutExpired:proc.kill();proc.wait();code=-1
  handle.close();output=path.read_text(encoding='utf-8')
  ok=code==0 and 'PASS' in output and 'SCRIPT ERROR' not in output
  print(name,role,'PASS' if ok else 'FAIL',flush=True)
  if not ok:failed.append(name+'_'+role)
print('Logs:',logs,'Failures:',failed)
sys.exit(bool(failed))
