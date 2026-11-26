extends SceneTree
## Opt-in smoke against a real Judge0 deployment. Submits only fixtures defined here.
const Execution=preload("res://scripts/campus/computers/ide_execution.gd")
const PROGRAMS:={
	"hello.py":"print('CAMPUS_IDE_42')",
	"hello.c":"#include <stdio.h>\nint main(void) { puts(\"CAMPUS_IDE_42\"); return 0; }",
	"hello.cpp":"#include <iostream>\nint main() { std::cout << \"CAMPUS_IDE_42\\n\"; }",
	"hello.cs":"class Program { static void Main() { System.Console.WriteLine(\"CAMPUS_IDE_42\"); } }",
	"Main.java":"public class Main { public static void main(String[] args) { System.out.println(\"CAMPUS_IDE_42\"); } }"
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var execution:=Execution.new()
	root.add_child(execution)
	execution.configure_from_host()
	var catalog:=await execution.supported_runtimes()
	if catalog.has("error"):
		push_error(str(catalog.error))
		quit(1)
		return
	var failures:=0
	for file: String in PROGRAMS:
		var result:=await execution.execute(file,PROGRAMS[file])
		if result.contains("Accepted") and result.contains("CAMPUS_IDE_42"):
			print("LIVE_COMPILER PASS ",file," · ",result.get_slice("\n",0))
		else:
			push_error("Compiler failed for "+file+": "+result)
			failures+=1
	quit(1 if failures>0 else 0)
