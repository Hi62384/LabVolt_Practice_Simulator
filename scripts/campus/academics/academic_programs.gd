extends RefCounted
## The campus curriculum's single program/course mapping. NPC admission and the
## course provider consume this same catalog; it never awards official marks.
const COURSES := ["ETY155", "ELM253", "DGS266", "MTH147", "MTH255"]
const PROGRAMS := {
    "electronics technology": ["ETY155", "ELM253", "DGS266", "MTH147", "MTH255"],
    "electrical engineering": ["ETY155", "ELM253", "DGS266", "MTH147", "MTH255"],
    "mechatronics": ["ETY155", "ELM253", "DGS266", "MTH147", "MTH255"],
    "software development": ["DGS266", "MTH147", "MTH255"],
    "mechanical technology": ["ETY155", "MTH147", "MTH255"],
    "audio technology": ["ETY155", "ELM253", "MTH147"],
    "general studies": ["MTH147"],
    "business": ["MTH147"],
    "design": [], "media production": [], "hospitality": [], "liberal studies": []
}
const ALIASES := {"electrical technology":"electronics technology", "electrical engineering technology":"electronics technology", "electronics engineering":"electrical engineering", "computer science":"software development", "mechanical engineering":"mechanical technology"}

static func normalize(program: String) -> String:
    var value := program.strip_edges().to_lower()
    return str(ALIASES.get(value, value))

static func courses_for(program: String) -> Array:
    return PROGRAMS.get(normalize(program), []).duplicate()

static func eligible(profile: Dictionary, course: String) -> bool:
    if course.is_empty(): return true
    if course not in COURSES: return false
    var enrollment: Variant = profile.get("enrollment", {})
    if not enrollment is Dictionary: return false
    # No prerequisite progression is currently defined by academic gameplay.
    # Explicit suspended/withdrawn enrollment still excludes a resident.
    if enrollment.get(course, "") in ["withdrawn", "suspended", "completed_only"]:return false
    return course in courses_for(str(profile.get("program", ""))) or enrollment.get(course, "")=="enrolled"

static func for_course(course: String, seed_value: int) -> String:
    var candidates := []
    for program in PROGRAMS:
        if course.is_empty() or course in PROGRAMS[program]:
            if not PROGRAMS[program].is_empty(): candidates.append(program)
    return str(candidates[posmod(seed_value, candidates.size())]) if not candidates.is_empty() else ""

static func eligible_courses(profile: Dictionary) -> Array:
    return COURSES.filter(func(course):return eligible(profile,str(course)))

static func catalog() -> Array:
    var result := []
    for program in PROGRAMS: result.append({"id":program, "name":program.capitalize(), "courses":courses_for(program)})
    return result
