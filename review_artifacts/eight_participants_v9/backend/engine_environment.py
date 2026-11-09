"""Engine-only explicit environment; case fix retained, no native dependency."""
from pathlib import Path
def build(source,folder):
    upper={str(key).upper():str(value) for key,value in source.items()}
    for key in ('SYSTEMROOT','SYSTEMDRIVE','USERPROFILE'):
        if not upper.get(key):raise RuntimeError('Missing required Windows environment: '+key)
    result={key:upper[key] for key in ('SYSTEMROOT','SYSTEMDRIVE','USERPROFILE')}
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP'):result[key]=str(Path(folder)/key.lower())
    result['PATH']=str(Path(upper['SYSTEMROOT'])/'System32')
    return result
