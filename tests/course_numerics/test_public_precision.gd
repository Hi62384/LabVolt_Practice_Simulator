extends SceneTree
# UNPARSED / UNRUN. Calls the actual production Quantity.check; no mock grader.
# Copy this and independent_expectation_vectors.json under res://tests/course_numerics/.
const Generator=preload("res://scripts/course_generator.gd")
const Quantity=preload("res://scripts/campus/courses/quantity.gd")
var checks := 0
var failures := 0
func verify(condition: bool,label: String) -> void:
    checks+=1
    if not condition:failures+=1;push_error(label)
func student_answer(topic: int,prompt: String,index: int) -> float:
    var regex := RegEx.new()
    var pattern := "^Parallel branches: ([0-9.]+) V across R = ([0-9.]+).*?XL = ([0-9.]+).*?XC = ([0-9.]+)" if topic==3 else "^Source ([0-9.]+) V.*R2 ([0-9.]+).*XL ([0-9.]+).*R1 ([0-9.]+).*XC ([0-9.]+)"
    if regex.compile(pattern)!=OK:push_error("Prompt regex failed");return NAN
    var found := regex.search(prompt)
    if found==null:push_error("Public prompt did not parse: "+prompt);return NAN
    var v := float(found.get_string(1))
    var r := float(found.get_string(2)) if topic==3 else float(found.get_string(4))
    var xl := float(found.get_string(3))
    var xc := float(found.get_string(4)) if topic==3 else float(found.get_string(5))
    if topic==3:
        var ir := v/r
        var il := v/xl
        var iq := -il+(v/xc if xc!=0 else 0.0)
        var answers := [ir,il,sqrt(ir*ir+iq*iq),v*v/r,v*v/xl-(v*v/xc if xc!=0 else 0.0)]
        return float(answers[index])
    var r2 := float(found.get_string(2))
    var denominator := r*r+xc*xc
    var pr := r*xc*xc/denominator
    var pi := -r*r*xc/denominator
    var zr := r2+pr
    var zi := xl+pi
    var current := v/sqrt(zr*zr+zi*zi)
    var answers := [zr,zi,current,current*sqrt(pr*pr+pi*pi),current*current*zr]
    return float(answers[index])
func _initialize() -> void:
    var path := "res://tests/course_numerics/independent_expectation_vectors.json"
    var loaded: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not loaded is Array:push_error("Missing independent vector array");quit(2);return
    verify(loaded.size()==732,"Expected complete 732 failing-comparison vectors")
    var counts := {3:0,4:0}
    for row in loaded:
        var topic := int(row.topic)
        var index := int(row.index)
        var id := str(row.id)
        counts[topic]+=1
        var original := student_answer(topic,str(row.original_public_prompt),index)
        var corrected := student_answer(topic,str(row.corrected_public_prompt),index)
        var target := float(row.expected_answer)
        var unit := str(row.unit)
        var q := {"answer":target,"unit":unit,"relative_tolerance":0.02,"absolute_tolerance_si":1e-9}
        # Expected values come from 50-digit independent vectors, never an answer key.
        verify(is_finite(original) and is_finite(corrected),id+": finite public calculations")
        verify(absf(original-float(row.original_student_answer))<=maxf(1e-10,absf(original)*1e-10),id+": original public oracle agreement")
        verify(absf(corrected-float(row.corrected_student_answer))<=maxf(1e-10,absf(corrected)*1e-10),id+": corrected public oracle agreement")
        # Format sufficiently many digits that presentation of the student's value
        # does not add another rounding defect. Calls production parser and grader.
        var old_raw := "%.15f %s"%[original,unit]
        var new_raw := "%.15f %s"%[corrected,unit]
        verify(not Quantity.check(q,old_raw).correct,id+": original rounded public result must reject")
        verify(Quantity.check(q,new_raw).correct,id+": corrected public result must accept")
        verify(Quantity.check(q,"%.15f %s"%[target,unit]).correct,id+": independent target must accept")
    verify(counts[3]==549 and counts[4]==183,"Per-topic regression vector counts")
    # Additionally exercise actual production generator/public-copy/grade interfaces.
    # This is separate from the independent-vector fixtures above.
    for topic in [3,4]:
        for difficulty in range(3):
            for seed_value in range(64):
                var assignment := Generator.generate(topic,difficulty,seed_value)
                var public := Generator.public_copy(assignment)
                var prompt := ""
                for line in str(public.data).split("\n"):
                    if str(line).begins_with("Parallel branches:" if topic==3 else "Source "):prompt=str(line);break
                verify(prompt!="","Generated public prompt exists")
                if prompt=="":continue
                var answers := {}
                for index in range(5):
                    var q: Dictionary=assignment.questions[index]
                    var calculated := student_answer(topic,prompt,index)
                    answers[str(index)]="%.15f %s"%[calculated,str(q.unit)]
                    verify(Quantity.check(q,answers[str(index)]).correct,"Generated published givens must grade correctly: topic%d d%d seed%d q%d"%[topic,difficulty,seed_value,index])
                verify(Generator.grade(assignment,answers).score==100.0,"Real generator grader accepts published calculation")
    print("PUBLIC_PRECISION_RESULT vectors=%d checks=%d failures=%d"%[loaded.size(),checks,failures])
    quit(0 if failures==0 else 1)
