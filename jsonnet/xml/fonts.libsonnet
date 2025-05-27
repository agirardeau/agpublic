local css = import './css.libsonnet';

{
  LATIN_MODERN_MATH: {
    import_rule: css.Import + {
      url: 'https://fonts.cdnfonts.com/css/latin-modern-math',
    },
    family: 'Latin Modern Math',
  },
  NOTO_SANS_MATH: {
    import_rule: css.Import + {
      url: 'https://fonts.googleapis.com/css2?family=Noto+Sans+Math&amp;display=swap',
    },
    family: 'Noto Sans Math',
  },
  STIX_TWO_TEXT: {
    import_rule: css.Import + {
      url: 'https://fonts.googleapis.com/css2?family=STIX+Two+Text:ital,wght@0,400..700;1,400..700&amp;display=swap'
    },
    // I think this doesn't work because the googleapis link is a stylesheet rather than an otf
    #local this = self,
    #import_rule: css.FontFace + {
    #  font_family_name: this.family,
    #  sources: [
    #    css.fns.url('https://fonts.googleapis.com/css2?family=STIX+Two+Text:ital,wght@0,400..700;1,400..700&amp;display=swap'),
    #  ],
    #},
    family: 'STIX Two Text',
  },
  CAMBRIA_MATH: {
    family: 'Cambria Math',
  },

  // Sans math font, not that great tbh
  GFS_NEOHELLENIC_MATH: {
    local this = self,
    import_rule: css.FontFace + {
      font_family_name: this.family,
      sources: [
        css.fns.url('https://mirrors.ctan.org/fonts/gfsneohellenicmath/GFSNeohellenicMath.otf'),
      ],
    },
    family: 'GFS Neohellenic Math',
  },
  #// This one might not be working
  #FIRA_MATH: {
  #  local this = self,
  #  import_rule: css.FontFace + {
  #    font_family_name: this.family,
  #    sources: [
  #      css.fns.url('https://github.com/firamath/firamath/releases/download/v0.3.4/FiraMath-Regular.otf'),
  #    ],
  #  },
  #  family: 'Fira Math',
  #},
}