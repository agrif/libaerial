#include <gst/gst.h>

GType airtunes_sink_get_type (void) G_GNUC_CONST;
gboolean plugin_init(GstPlugin*);

#define PACKAGE "airtunes"

GST_PLUGIN_DEFINE (
	GST_VERSION_MAJOR,
	GST_VERSION_MINOR,
	airtunes,
	"Airtunes Sink",
	plugin_init,
	"0.0.0", // TODO version
	"LGPL",
	"airtunes",
	"http://github.com/agrif/airtunes"
)
