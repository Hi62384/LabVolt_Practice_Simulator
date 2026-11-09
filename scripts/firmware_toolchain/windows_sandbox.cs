// Trusted broker implementation; no player text is compiled as managed code.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace LabVolt.Toolchain {
public sealed class WindowsSandbox : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct SECURITY_CAPABILITIES { public IntPtr sid, capabilities; public uint count, reserved; }
    [StructLayout(LayoutKind.Sequential)] struct SECURITY_ATTRIBUTES { public int length; public IntPtr descriptor; [MarshalAs(UnmanagedType.Bool)] public bool inherit; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO { public int cb; public string reserved,desktop,title; public int x,y,cx,cy,xchars,ychars,fill,flags; public short show,reserved2; public IntPtr reservedPtr,input,output,error; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFOEX { public STARTUPINFO startup; public IntPtr attributes; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr process,thread; public uint pid,tid; }
    [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT { public long processTime,jobTime; public uint flags; public UIntPtr minWorking,maxWorking; public uint active; public UIntPtr affinity; public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT { public BASIC_LIMIT basic; public IO_COUNTERS io; public UIntPtr processMemory,jobMemory,peakProcess,peakJob; }
    [StructLayout(LayoutKind.Sequential)] struct CPU_RATE { public uint flags,rate; }
    [StructLayout(LayoutKind.Sequential)] struct FILE_TIME { public uint low,high; }
    [StructLayout(LayoutKind.Sequential)] struct FILE_INFO { public uint attributes; public FILE_TIME created,accessed,written; public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow; }
    [DllImport("userenv.dll",CharSet=CharSet.Unicode)] static extern int CreateAppContainerProfile(string name,string display,string description,IntPtr capabilities,uint count,out IntPtr sid);
    [DllImport("userenv.dll",CharSet=CharSet.Unicode)] static extern int DeleteAppContainerProfile(string name);
    [DllImport("advapi32.dll")] static extern IntPtr FreeSid(IntPtr sid);
    [DllImport("userenv.dll",CharSet=CharSet.Unicode)] static extern int GetAppContainerFolderPath(string sid,out IntPtr path);
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,IntPtr data,uint length);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,int flags,ref IntPtr bytes);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attribute,IntPtr value,IntPtr bytes,IntPtr previous,IntPtr returned);
    [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll",EntryPoint="CreateProcessW",ExactSpelling=true,CharSet=CharSet.Unicode,SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)] static extern bool CreateProcessW(string app,StringBuilder command,IntPtr processAttributes,IntPtr threadAttributes,bool inherit,uint flags,IntPtr environment,string directory,ref STARTUPINFOEX startup,out PROCESS_INFORMATION process);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string path,uint access,uint share,ref SECURITY_ATTRIBUTES attributes,uint create,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr handle,out FILE_INFO info);
    readonly string profile="LabVolt.Compiler."+Guid.NewGuid().ToString("N");
    IntPtr sid=IntPtr.Zero,job=IntPtr.Zero;
    readonly List<KeyValuePair<string,byte[]>> aclBackups=new List<KeyValuePair<string,byte[]>>();
    readonly Stopwatch lifetime=Stopwatch.StartNew();
    public bool IsolationExercised { get; private set; }
    public string Isolation { get { return "Windows LPAC, no capabilities, job-limited"; } }
    public WindowsSandbox() {
        int hr=CreateAppContainerProfile(profile,"LabVolt isolated compiler","Temporary offline firmware compiler",IntPtr.Zero,0,out sid);
        if(hr!=0) throw new InvalidOperationException("CreateAppContainerProfile failed: 0x"+hr.ToString("X8")+". No compiler executed; no reduced-isolation fallback.");
        try {
            job=CreateJobObject(IntPtr.Zero,null); Ensure(job!=IntPtr.Zero,"CreateJobObject");
            EXTENDED_LIMIT limits=new EXTENDED_LIMIT();
            // KILL_ON_JOB_CLOSE, PROCESS_MEMORY, JOB_MEMORY, ACTIVE_PROCESS, JOB_TIME.
            limits.basic.flags=0x2000|0x100|0x200|0x8|0x4; limits.basic.active=8;
            limits.basic.jobTime=60L*10000000L; limits.processMemory=(UIntPtr)(512UL*1024*1024); limits.jobMemory=(UIntPtr)(768UL*1024*1024);
            SetJob(9,limits);
            CPU_RATE cpu=new CPU_RATE();cpu.flags=0x1|0x4;cpu.rate=5000;SetJob(15,cpu);
            // The implicit per-profile storage must not become an unmonitored
            // second writable filesystem. All compiler temp files use the job.
            IntPtr folder;int folderResult=GetAppContainerFolderPath(new SecurityIdentifier(sid).Value,out folder);
            if(folderResult!=0)throw new InvalidOperationException("Cannot locate isolated profile storage: 0x"+folderResult.ToString("X8"));
            try {
                string profilePath=Marshal.PtrToStringUni(folder);
                DirectorySecurity profileAcl=Directory.GetAccessControl(profilePath);
                profileAcl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid),FileSystemRights.Write|FileSystemRights.Delete|FileSystemRights.DeleteSubdirectoriesAndFiles,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Deny));
                Directory.SetAccessControl(profilePath,profileAcl);
            } finally {Marshal.FreeCoTaskMem(folder);}
        } catch { Dispose();throw; }
    }
    static void Ensure(bool ok,string operation) { if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error(),operation); }
    void SetJob<T>(int info,T value) { IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(T)));try { Marshal.StructureToPtr(value,p,false);Ensure(SetInformationJobObject(job,info,p,(uint)Marshal.SizeOf(typeof(T))),"SetInformationJobObject"); } finally {Marshal.FreeHGlobal(p);} }
    public void GrantDirectory(string directory,bool write) {
        string path=Path.GetFullPath(directory);
        foreach(string item in Directory.EnumerateFileSystemEntries(path,"*",SearchOption.AllDirectories))
            if((File.GetAttributes(item)&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("Reparse points are forbidden in compiler roots");
        DirectorySecurity acl=Directory.GetAccessControl(path);
        aclBackups.Add(new KeyValuePair<string,byte[]>(path,acl.GetSecurityDescriptorBinaryForm()));
        SecurityIdentifier identity=new SecurityIdentifier(sid);
        FileSystemRights rights=write?FileSystemRights.Modify:FileSystemRights.ReadAndExecute;
        acl.AddAccessRule(new FileSystemAccessRule(identity,rights,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
        Directory.SetAccessControl(path,acl);
        if(write) {
            // Mandatory integrity is separate from the AppContainer's DACL access.
            ProcessStartInfo start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","icacls.exe"));
            start.Arguments=Quote(path)+" /setintegritylevel (OI)(CI)L";start.UseShellExecute=false;start.CreateNoWindow=true;start.RedirectStandardOutput=true;start.RedirectStandardError=true;
            using(Process p=Process.Start(start)) { string ignored=p.StandardOutput.ReadToEnd()+p.StandardError.ReadToEnd(); if(!p.WaitForExit(5000)||p.ExitCode!=0)throw new InvalidOperationException("Cannot set low-integrity job directory: "+ignored); }
        }
    }
    public static string Quote(string value) {
        StringBuilder s=new StringBuilder("\"");int backslashes=0;
        foreach(char c in value) { if(c=='\\'){backslashes++;continue;} if(c=='\"'){s.Append('\\',backslashes*2+1);s.Append(c);backslashes=0;continue;} s.Append('\\',backslashes);backslashes=0;s.Append(c); }
        s.Append('\\',backslashes*2);s.Append('"');return s.ToString();
    }
    // Pure construction: never inherit the caller's full environment or secrets.
    public static string BuildChildEnvironment(string executable,string directory,string windows) {
        if(String.IsNullOrWhiteSpace(windows)||!Path.IsPathRooted(windows))throw new InvalidOperationException("Windows system root must be an absolute path");
        if(!Path.IsPathRooted(executable)||!Path.IsPathRooted(directory))throw new InvalidOperationException("Compiler and job paths must be absolute");
        if(executable.IndexOf('\0')>=0||directory.IndexOf('\0')>=0||windows.IndexOf('\0')>=0)throw new InvalidOperationException("NUL in trusted launch path");
        string system=Path.Combine(windows,"System32");
        var values=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase) {
            {"APPDATA",directory}, {"ComSpec",Path.Combine(system,"cmd.exe")},
            {"LOCALAPPDATA",directory},
            {"PATH",Path.GetDirectoryName(executable)+";"+system},
            {"SystemDrive",Path.GetPathRoot(windows).TrimEnd('\\')},
            {"SystemRoot",windows}, {"TEMP",directory}, {"TMP",directory},
            {"USERPROFILE",directory}, {"windir",windows}
        };
        StringBuilder block=new StringBuilder();
        foreach(var pair in values)block.Append(pair.Key).Append('=').Append(pair.Value).Append('\0');
        return block.Append('\0').ToString();
    }
    public int Run(string executable,string[] args,string directory,string log,string cancel,int timeoutMs) {
        if(lifetime.ElapsedMilliseconds>90000)throw new TimeoutException("Aggregate compiler wall limit reached");
        IntPtr list=IntPtr.Zero,size=IntPtr.Zero,caps=IntPtr.Zero,policy=IntPtr.Zero,handles=IntPtr.Zero,environment=IntPtr.Zero;
        IntPtr stdout=IntPtr.Zero,stdin=IntPtr.Zero;PROCESS_INFORMATION process=new PROCESS_INFORMATION();bool created=false,assigned=false;
        try {
            SECURITY_ATTRIBUTES security=new SECURITY_ATTRIBUTES();security.length=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));security.inherit=true;
            // CREATE_NEW refuses guest-precreated links instead of following them.
            stdout=CreateFile(log,0x40000000,3,ref security,1,0x80,IntPtr.Zero);Ensure(stdout!=new IntPtr(-1),"Create new output file");
            stdin=CreateFile("NUL",0x80000000,3,ref security,3,0x80,IntPtr.Zero);Ensure(stdin!=new IntPtr(-1),"Open NUL input");
            InitializeProcThreadAttributeList(IntPtr.Zero,3,0,ref size);list=Marshal.AllocHGlobal(size);
            Ensure(InitializeProcThreadAttributeList(list,3,0,ref size),"InitializeProcThreadAttributeList");
            SECURITY_CAPABILITIES capabilities=new SECURITY_CAPABILITIES();capabilities.sid=sid;
            caps=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)));Marshal.StructureToPtr(capabilities,caps,false);
            Ensure(UpdateProcThreadAttribute(list,0,(IntPtr)0x20009,caps,(IntPtr)Marshal.SizeOf(typeof(SECURITY_CAPABILITIES)),IntPtr.Zero,IntPtr.Zero),"Set AppContainer capabilities");
            policy=Marshal.AllocHGlobal(4);Marshal.WriteInt32(policy,1);
            Ensure(UpdateProcThreadAttribute(list,0,(IntPtr)0x2000F,policy,(IntPtr)4,IntPtr.Zero,IntPtr.Zero),"Enforce LPAC opt-out");
            handles=Marshal.AllocHGlobal(IntPtr.Size*2);Marshal.WriteIntPtr(handles,0,stdout);Marshal.WriteIntPtr(handles,IntPtr.Size,stdin);
            Ensure(UpdateProcThreadAttribute(list,0,(IntPtr)0x20002,handles,(IntPtr)(IntPtr.Size*2),IntPtr.Zero,IntPtr.Zero),"Whitelist inherited handles");
            STARTUPINFOEX startup=new STARTUPINFOEX();startup.startup.cb=Marshal.SizeOf(typeof(STARTUPINFOEX));startup.attributes=list;
            startup.startup.flags=0x100;startup.startup.input=stdin;startup.startup.output=stdout;startup.startup.error=stdout;
            StringBuilder command=new StringBuilder(Quote(executable));foreach(string a in args)command.Append(" ").Append(Quote(a));
            // A minimal environment prevents compiler search paths, injected DLL search
            // and user-provided temp/plugin settings from entering the container.
            string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string env=BuildChildEnvironment(executable,directory,windows);
            environment=Marshal.StringToHGlobalUni(env);
            const uint launchFlags=0x80000|0x4|0x400|0x08000000; // EXTENDED, SUSPENDED, UNICODE, NO_WINDOW
            bool launched=CreateProcessW(executable,command,IntPtr.Zero,IntPtr.Zero,true,launchFlags,environment,directory,ref startup,out process);
            int launchError=launched?0:Marshal.GetLastWin32Error(); // Capture before any further native call.
            if(!launched)throw new Win32Exception(launchError,"Create isolated compiler failed (Win32 "+launchError+"; "+new Win32Exception(launchError).Message+"; flags=0x"+launchFlags.ToString("X8")+"; explicit UTF-16 environment; explicit job working directory)");
            created=true;
            Ensure(AssignProcessToJobObject(job,process.process),"Assign isolated compiler job");
            assigned=true;
            Ensure(ResumeThread(process.thread)!=0xffffffff,"Resume isolated compiler");
            IsolationExercised=true;
            Stopwatch elapsed=Stopwatch.StartNew();
            while(WaitForSingleObject(process.process,50)==0x102) {
                if(File.Exists(cancel))throw new OperationCanceledException("Compilation cancelled");
                if(elapsed.ElapsedMilliseconds>timeoutMs||lifetime.ElapsedMilliseconds>90000)throw new TimeoutException("Compiler wall time exceeded");
                if(File.Exists(log)&&new FileInfo(log).Length>262144)throw new InvalidOperationException("Compiler diagnostic output limit exceeded");
                CheckTree(directory);
            }
            CheckTree(directory);
            if(File.Exists(log)&&new FileInfo(log).Length>262144)throw new InvalidOperationException("Compiler diagnostic output limit exceeded");
            uint exit;Ensure(GetExitCodeProcess(process.process,out exit),"Get compiler exit code");return unchecked((int)exit);
        } catch {
            if(created) {
                if(assigned)TerminateJobObject(job,125);
                else TerminateProcess(process.process,125); // Owned, still-suspended child never entered the job.
                WaitForSingleObject(process.process,2000);
            }
            throw;
        }
        finally {
            if(process.thread!=IntPtr.Zero)CloseHandle(process.thread);if(process.process!=IntPtr.Zero)CloseHandle(process.process);
            if(stdout!=IntPtr.Zero&&stdout!=new IntPtr(-1))CloseHandle(stdout);if(stdin!=IntPtr.Zero&&stdin!=new IntPtr(-1))CloseHandle(stdin);
            if(list!=IntPtr.Zero){DeleteProcThreadAttributeList(list);Marshal.FreeHGlobal(list);}if(caps!=IntPtr.Zero)Marshal.FreeHGlobal(caps);if(policy!=IntPtr.Zero)Marshal.FreeHGlobal(policy);if(handles!=IntPtr.Zero)Marshal.FreeHGlobal(handles);if(environment!=IntPtr.Zero)Marshal.FreeHGlobal(environment);
        }
    }
    public void Stop() { if(job!=IntPtr.Zero)TerminateJobObject(job,125); }
    public static byte[] ReadBytes(string path,int maximum) {
        SECURITY_ATTRIBUTES attributes=new SECURITY_ATTRIBUTES();attributes.length=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
        IntPtr handle=CreateFile(path,0x80000000,1,ref attributes,3,0x00200000,IntPtr.Zero);
        Ensure(handle!=new IntPtr(-1),"Open bounded compiler output without following links");
        using(SafeFileHandle safe=new SafeFileHandle(handle,true)) {
            FILE_INFO info;Ensure(GetFileInformationByHandle(handle,out info),"Inspect compiler output handle");
            if((info.attributes&0x400)!=0||info.links!=1||info.sizeHigh!=0||info.sizeLow>maximum)throw new InvalidOperationException("Compiler output link or size limit rejected");
            using(FileStream stream=new FileStream(safe,FileAccess.Read)) {
                byte[] bytes=new byte[(int)info.sizeLow];int offset=0;
                while(offset<bytes.Length){int n=stream.Read(bytes,offset,bytes.Length-offset);if(n==0)throw new IOException("Truncated compiler output");offset+=n;}
                return bytes;
            }
        }
    }
    public static string ReadText(string path,int maximum) { return Encoding.UTF8.GetString(ReadBytes(path,maximum)); }
    public static void CheckTree(string directory) {
        long bytes=0;int count=0;Queue<string> folders=new Queue<string>();folders.Enqueue(directory);
        while(folders.Count>0)foreach(string path in Directory.EnumerateFileSystemEntries(folders.Dequeue())) {
            FileAttributes flags=File.GetAttributes(path);
            if((flags&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("Compiler produced a forbidden reparse point");
            if(++count>256)throw new InvalidOperationException("Compiler workspace entry limit exceeded");
            if((flags&FileAttributes.Directory)!=0)folders.Enqueue(path);else bytes+=new FileInfo(path).Length;
            if(bytes>32L*1024*1024)throw new InvalidOperationException("Compiler workspace byte monitor exceeded");
        }
    }
    public static void CleanupJob(string directory) {
        Guid id;if(!Guid.TryParseExact(Path.GetFileName(Path.GetFullPath(directory)),"N",out id))return;
        foreach(string entry in Directory.EnumerateFileSystemEntries(directory)) {
            if(Path.GetFileName(entry)=="result.json")continue;
            RemoveEntry(entry);
        }
    }
    static void RemoveEntry(string path) {
        FileAttributes flags=File.GetAttributes(path);
        if((flags&FileAttributes.Directory)!=0) {
            if((flags&FileAttributes.ReparsePoint)==0)foreach(string entry in Directory.EnumerateFileSystemEntries(path))RemoveEntry(entry);
            Directory.Delete(path,false);
        } else File.Delete(path);
    }
    public void Dispose() {
        if(job!=IntPtr.Zero){TerminateJobObject(job,125);CloseHandle(job);job=IntPtr.Zero;}
        for(int i=aclBackups.Count-1;i>=0;i--) { try {DirectorySecurity acl=new DirectorySecurity();acl.SetSecurityDescriptorBinaryForm(aclBackups[i].Value);Directory.SetAccessControl(aclBackups[i].Key,acl);} catch {} }
        aclBackups.Clear();if(sid!=IntPtr.Zero){FreeSid(sid);sid=IntPtr.Zero;DeleteAppContainerProfile(profile);}
    }
}
}
