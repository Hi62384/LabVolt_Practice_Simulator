# Campus OS

Campus OS runs on the existing workstation session and virtual drive. Workstations preserve windows while powered on. Power-off still clears a public workstation's temporary files. Attachments, saved files, and assignment actions continue through the existing device and school authority.

Files and Terminal share the same virtual workspace. Terminal commands are help, clear, pwd, ls, cd, mkdir, touch, cat, echo, open, and date. Folder mutations require a device that supports folders. The workstation's internal drive supports recoverable deletion. The USB workflow continues to use its existing explicit permanent-delete confirmation and archive writes.

## CampusScript

Use the Code Editor to run a file ending in .campus. Programs accept arithmetic, comparisons, numeric variables, parentheses, and the functions abs, sqrt, sin, cos, tan, log, exp, pow, min, max, floor, ceil, and round. Use # to start a comment.

    let voltage = 12
    let resistance = 100
    print voltage / resistance
    repeat 3
        let resistance = resistance + 10
        if resistance > 120
            print resistance
        end
    end

The interpreter has limits for source size, executed statements, loop iterations, nesting, variables, and output. Other source formats are editable. Circuit Lab calculates ideal DC steady-state and single-frequency AC series or parallel circuits and stores projects as validated virtual .circuit documents.
