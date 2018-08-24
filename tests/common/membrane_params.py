
def set_lina(lscale, p):
    p.x0        = 0.457
    p.p         = 0.000906667 * lscale
    p.ka        = 4900.0
    p.kb        = 44.4444 * lscale**2
    p.kd        = 5000
    p.kv        = 7500.0
    p.gammaC    = 52.0 * lscale
    p.gammaT    = 0.0
    p.kbT       = 0.0444 * lscale**2
    p.mpow      = 2.0
    p.theta     = 6.97
    p.totArea   = 62.2242 * lscale**2
    p.totVolume = 26.6649 * lscale**3
    p.ks        = p.kbT / p.p
