extends RefCounted
## Authoritative Class activity kind decides availability; course supports both tracks.
static func allowed(mode: String,activity: Dictionary) -> bool:
	if mode!="Class":return true
	return str(activity.get("mode",""))=="Course" and str(activity.get("kind",""))=="lab"
