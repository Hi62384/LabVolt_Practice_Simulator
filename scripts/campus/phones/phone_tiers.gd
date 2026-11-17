extends RefCounted
## Storage is a photo quota, not a general-purpose filesystem.
const TIERS:={
	"basic":{"name":"Basic smartphone","price":250,"storage_bytes":4*1024*1024,"delay_ms":600,"display_scale":0.65},
	"standard":{"name":"Standard smartphone","price":650,"storage_bytes":16*1024*1024,"delay_ms":250,"display_scale":0.82},
	"premium":{"name":"Premium smartphone","price":1200,"storage_bytes":64*1024*1024,"delay_ms":0,"display_scale":1.0},
}
