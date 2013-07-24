#include <gst/gst.h>

GType aerial_sink_get_type (void) G_GNUC_CONST;
gboolean aerial_plugin_init(GstPlugin*);

GST_PLUGIN_DEFINE (
	GST_VERSION_MAJOR,
	GST_VERSION_MINOR,
	aerial,
	"Aerial Airtunes Sink",
	aerial_plugin_init,
	PACKAGE_VERSION,
	"LGPL",
	PACKAGE_NAME,
	PACKAGE_URL
)
