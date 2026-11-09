# Pure fixed-flag build planner. Production broker always constructs LPAC first.
# No execution occurs in this module. Only trusted host code invokes a plan.
function New-LabVoltCompilePlan {
    param([string]$ToolRoot,$Target,[string]$Board,[string]$SourceDirectory,[string]$BuildDirectory,[string]$SupportDirectory)
    $utf8=New-Object Text.UTF8Encoding($false)
    $commands=New-Object 'System.Collections.Generic.List[object]'
    $objects=New-Object 'System.Collections.Generic.List[string]'
    $compiler=Under-Root $ToolRoot ([string]$Target.cxx)
    $cc=Under-Root $ToolRoot ([string]$Target.cc)
    $objcopy=Under-Root $ToolRoot ([string]$Target.objcopy)
    $objdump=Under-Root $ToolRoot ([string]$Target.objdump)
    $common=@();$link=@();$coreSources=@()
    if($Board -in @('uno','nano')) {
        $core=Under-Root $ToolRoot ([string]$Target.core);$variant=Under-Root $ToolRoot ([string]$Target.variant)
        $boardMacro=if($Board -eq 'nano'){'-DARDUINO_AVR_NANO'}else{'-DARDUINO_AVR_UNO'}
        $common=@('-mmcu=atmega328p','-DF_CPU=16000000L','-DARDUINO=10819',$boardMacro,'-DARDUINO_ARCH_AVR','-Os','-g','-ffunction-sections','-fdata-sections','-I'+$core,'-I'+$variant,'-I'+$SourceDirectory)
        $link=@('-mmcu=atmega328p','-Wl,--gc-sections')
        $coreSources=@(Get-ChildItem -LiteralPath $core -File | Where-Object {$_.Extension -in @('.c','.cpp','.S')})
        # Only shipped official platform libraries are selectable. No package
        # installation, build hooks, arbitrary -I paths or user compiler flags.
        $platform=Split-Path -Parent (Split-Path -Parent $core)
        $sourceText=''
        foreach($file in Get-ChildItem -LiteralPath $SourceDirectory -File){$sourceText+=[IO.File]::ReadAllText($file.FullName)+"`n"}
        foreach($library in @('SPI','Wire','EEPROM','SoftwareSerial')){
            if($sourceText -notmatch ('#\s*include\s*[<"]\s*'+$library+'\.h[>"]')){continue}
            $libraryRoot=Join-Path $platform ('libraries\'+$library+'\src')
            if(-not [IO.Directory]::Exists($libraryRoot)){throw ('Official platform library missing: '+$library)}
            $common+=@('-I'+$libraryRoot)
            $coreSources+=@(Get-ChildItem -LiteralPath $libraryRoot -Recurse -File|Where-Object {$_.Extension -in @('.c','.cpp','.S')})
        }
    } else {
        $support=$SupportDirectory
        # Trusted support is copied; guest compilation cannot overwrite its original.
        foreach($file in Get-ChildItem -LiteralPath $support -File){[IO.File]::Copy($file.FullName,(Join-Path $BuildDirectory $file.Name),$true)}
        $common=@('-mcpu=cortex-m0plus','-mthumb','-Os','-g','-ffreestanding','-ffunction-sections','-fdata-sections','-I'+$SourceDirectory,'-I'+$BuildDirectory)
        $link=@('-mcpu=cortex-m0plus','-mthumb','-nostdlib','-Wl,--gc-sections','-T'+(Join-Path $BuildDirectory 'flash.ld'))
        $coreSources=@(Get-Item -LiteralPath (Join-Path $BuildDirectory 'startup.c'))
    }
    $translation=@(Get-ChildItem -LiteralPath $SourceDirectory -File | Where-Object {$_.Extension -in @('.ino','.cpp','.c')})+$coreSources
    $index=0
    foreach($unit in $translation){
        $inputFile=$unit.FullName
        if($unit.Extension -eq '.ino'){
            $inputFile=Join-Path $BuildDirectory ($unit.Name+'.cpp')
            [IO.File]::WriteAllText($inputFile,('#include <Arduino.h>'+"`n"+'#line 1 "'+$unit.Name+'"'+"`n"+[IO.File]::ReadAllText($unit.FullName)),$utf8)
        }
        $object=Join-Path $BuildDirectory ('unit'+$index+'.o');$index++;$objects.Add($object)
        $exe=$compiler;$compileArguments=$common+@('-fno-exceptions','-fno-rtti','-fno-threadsafe-statics','-std=gnu++11')
        if($unit.Extension -eq '.c'){$exe=$cc;$compileArguments=$common+@('-std=gnu11')}
        if($unit.Extension -eq '.S'){$exe=$cc;$compileArguments=$common+@('-x','assembler-with-cpp')}
        $commands.Add(@{exe=$exe;args=($compileArguments+@('-c',$inputFile,'-o',$object))})
    }
    $elf=Join-Path $BuildDirectory 'firmware.elf'
    $libraries=@('-lm')
    if($Board -eq 'pico'){$libraries+=@('-lgcc')}
    $commands.Add(@{exe=$compiler;args=($link+@('-o',$elf)+$objects.ToArray()+$libraries)})
    $image=Join-Path $BuildDirectory $(if($Board -in @('uno','nano')){'firmware.hex'}else{'firmware.bin'})
    $commands.Add(@{exe=$objcopy;args=@('-O',$(if($Board -in @('uno','nano')){'ihex'}else{'binary'}),'-R','.eeprom',$elf,$image)})
    return @{commands=$commands;elf=$elf;image=$image;objdump=$objdump;build=$BuildDirectory}
}
