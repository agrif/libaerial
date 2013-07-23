#include <gst/gst.h>

GType aerial_sink_get_type (void) G_GNUC_CONST;
gboolean aerial_plugin_init(GstPlugin*);

#define PACKAGE "aerial"

GST_PLUGIN_DEFINE (
	GST_VERSION_MAJOR,
	GST_VERSION_MINOR,
	aerial,
	"Aerial Airtunes Sink",
	aerial_plugin_init,
	"0.0.0", // TODO version
	"LGPL",
	"libaerial",
	"http://github.com/agrif/libaerial"
)
