import sys, os, subprocess, glob
import sphinx.ext.autodoc

extensions = ['breathe', 'sphinx.ext.mathjax', 'sphinx.ext.autodoc', 'sphinx.ext.napoleon']

add_module_names = False

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# The suffix of source filenames.
source_suffix = '.rst'

# The encoding of source files.
#source_encoding = 'utf-8-sig'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = 'uDeviceX'
copyright = 'ETH Zurich'
author = 'Dmitry Alexeev'

exclude_patterns = []
pygments_style = 'sphinx'
html_static_path = ['_static']
html_theme = 'sphinx_rtd_theme'
html_theme_path = ["_themes",]
import sphinx_rtd_theme
html_theme_path = [sphinx_rtd_theme.get_html_theme_path()]
html_title = "uDeviceX"


# If false, no module index is generated.
html_domain_indices = True

# If false, no index is generated.
html_use_index = True

# If true, the index is split into individual pages for each letter.
html_split_index = False

# If true, links to the reST sources are added to the pages.
html_show_sourcelink = False

# If true, "Created using Sphinx" is shown in the HTML footer. Default is True.
html_show_sphinx = False

# If true, "(C) Copyright ..." is shown in the HTML footer. Default is True.
html_show_copyright = True


breathe_projects = { 'uDeviceX': '../xml' }
breathe_default_project = 'uDeviceX'
breathe_domain_by_extension = { "h" : "cpp", "cu" : "cpp" }

cpp_id_attributes = ['__device__', '__global__', '__host__']
cpp_paren_attributes = ['__launch_bounds__', '__align__']

suppress_warnings = ['']

on_rtd = os.environ.get('READTHEDOCS', None) == 'True'

# Override some fuck
def format_signature(self):
    if self.args is not None:
        # signature given explicitly
        args = "(%s)" % self.args  # type: unicode
    else:
        # try to introspect the signature
        try:
            args = self.format_args()
        except Exception as err:
            #logger.warning(__('error while formatting arguments for %s: %s') %
            #                (self.fullname, err))
            args = None

    retann = self.retann

    result = self.env.app.emit_firstresult(
        'autodoc-process-signature', self.objtype, self.fullname,
        self.object, self.options, args, retann)
    if result:
        args, retann = result

    if args is not None:
        return args + (retann and (' -> %s' % retann) or '')
    else:
        return ''

def setup(app):
    app.add_stylesheet('css/theme.css')
    
    if not on_rtd:
        sys.path.append('../src')
        sys.path.append('../build')
        import udevicex
        
        sphinx.ext.autodoc.Documenter.format_signature = format_signature

if on_rtd:
    subprocess.call('cd ..; doxygen', shell=True)
    
    src = glob.glob('user/*.rst')
    gen = glob.glob('user/*.rst.gen')

    for s in src:
        os.rename(s, s+'.bak')
        
    for g in gen:
        os.rename(g, g[:-4])

