# T2.4b — Composition score calibration

- sample: 300 ids per mode, seed 20260821, drawn from L1..1500
- budget: 200ms (production path)
- score: unweighted mean of the five 0..1 rule sub-scores (T2.4a)
- Easy is excluded: `evaluateVisualComposition` short-circuits for the easy tier, so it has no composition measurement at all.

## MEDIUM

```
  SHIPPED (known-good)           n=   300  min=0.3810  p10=0.6059  p25=0.6722  p50=0.7640  p75=0.8733  p90=0.9481  max=1.0000
  candidates ACCEPTED by rules   n=  1004  min=0.3558  p10=0.5849  p25=0.6591  p50=0.7500  p75=0.8608  p90=0.9500  max=1.0000
  candidates REJECTED by rules   n=  2006  min=0.1822  p10=0.3837  p25=0.4373  p50=0.4846  p75=0.5537  p90=0.6167  max=0.8222

    shipped.aspect               n=   300  min=0.0000  p10=0.6296  p25=0.7778  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.3086  p10=0.5102  p25=0.5625  p50=0.7656  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.2679  p10=0.3750  p25=0.4167  p50=0.5185  p75=0.6000  p90=0.7500  max=1.0000
    shipped.singleton            n=   300  min=0.5000  p10=0.7500  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.2000  p10=0.3333  p25=0.5000  p50=0.6667  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=1814 singleton=0 occupancy=70 blobVsGrid=110 aspect=12
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6059 would sit below 88.0% of currently-rejected candidates and 12.5% of currently-accepted ones.

## HARD

```
  SHIPPED (known-good)           n=   300  min=0.5535  p10=0.6764  p25=0.7264  p50=0.8059  p75=0.8514  p90=0.8926  max=0.9133
  candidates ACCEPTED by rules   n=  1727  min=0.4567  p10=0.6593  p25=0.7181  p50=0.7868  p75=0.8354  p90=0.8819  max=0.9133
  candidates REJECTED by rules   n=   990  min=0.3667  p10=0.4781  p25=0.5020  p50=0.5581  p75=0.6126  p90=0.6520  max=0.8203

    shipped.aspect               n=   300  min=0.1667  p10=0.4444  p25=0.6825  p50=0.8095  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.3600  p10=0.6563  p25=0.7500  p50=0.8750  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.3906  p10=0.4464  p25=0.5102  p50=0.5102  p75=0.5952  p90=0.6944  max=0.8333
    shipped.singleton            n=   300  min=0.5000  p10=0.7500  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.2000  p10=0.3333  p25=0.6667  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=942 singleton=0 occupancy=0 blobVsGrid=38 aspect=10
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6764 would sit below 92.8% of currently-rejected candidates and 13.6% of currently-accepted ones.

