# T2.4b — Composition score calibration

- sample: 300 ids per mode, seed 20260821, drawn from L1..1500
- budget: 200ms (production path)
- score: unweighted mean of the five 0..1 rule sub-scores (T2.4a)
- Easy is excluded: `evaluateVisualComposition` short-circuits for the easy tier, so it has no composition measurement at all.

## MEDIUM

```
  SHIPPED (known-good)           n=   300  min=0.3810  p10=0.6514  p25=0.7345  p50=0.8075  p75=0.9111  p90=0.9630  max=1.0000
  candidates ACCEPTED by rules   n=   912  min=0.3558  p10=0.5892  p25=0.6676  p50=0.7544  p75=0.8733  p90=0.9600  max=1.0000
  candidates REJECTED by rules   n=  2354  min=0.2407  p10=0.3929  p25=0.4437  p50=0.4920  p75=0.5556  p90=0.6167  max=0.8222

    shipped.aspect               n=   300  min=0.0000  p10=0.6296  p25=0.7778  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.3200  p10=0.5000  p25=0.6049  p50=0.8889  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.2083  p10=0.3878  p25=0.4444  p50=0.5333  p75=0.6429  p90=0.8148  max=1.0000
    shipped.singleton            n=   300  min=0.5000  p10=0.7500  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.1667  p10=0.3333  p25=0.6667  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=2156 singleton=0 occupancy=75 blobVsGrid=113 aspect=10
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6514 would sit below 94.3% of currently-rejected candidates and 22.1% of currently-accepted ones.

## HARD

```
  SHIPPED (known-good)           n=   300  min=0.5121  p10=0.6948  p25=0.7486  p50=0.8087  p75=0.8552  p90=0.8926  max=0.9133
  candidates ACCEPTED by rules   n=  1406  min=0.5097  p10=0.6701  p25=0.7187  p50=0.7868  p75=0.8270  p90=0.8592  max=0.9133
  candidates REJECTED by rules   n=  1483  min=0.3653  p10=0.4781  p25=0.5262  p50=0.5781  p75=0.6281  p90=0.6520  max=0.8203

    shipped.aspect               n=   300  min=0.1667  p10=0.5556  p25=0.7222  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.3600  p10=0.6563  p25=0.7656  p50=0.8750  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.3906  p10=0.4219  p25=0.4464  p50=0.5102  p75=0.5208  p90=0.5952  max=0.8333
    shipped.singleton            n=   300  min=0.4286  p10=0.7500  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.1667  p10=0.3333  p25=0.6667  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=1451 singleton=0 occupancy=0 blobVsGrid=27 aspect=5
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6948 would sit below 96.3% of currently-rejected candidates and 17.9% of currently-accepted ones.

