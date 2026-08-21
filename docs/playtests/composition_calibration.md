# T2.4b — Composition score calibration

- sample: 300 ids per mode, seed 20260821, drawn from L1..1500
- budget: 200ms (production path)
- score: unweighted mean of the five 0..1 rule sub-scores (T2.4a)
- Easy is excluded: `evaluateVisualComposition` short-circuits for the easy tier, so it has no composition measurement at all.

## MEDIUM

```
  SHIPPED (known-good)           n=   300  min=0.4683  p10=0.6327  p25=0.6928  p50=0.7624  p75=0.9037  p90=0.9556  max=1.0000
  candidates ACCEPTED by rules   n=   810  min=0.4476  p10=0.6302  p25=0.6937  p50=0.7944  p75=0.9167  p90=0.9750  max=1.0000
  candidates REJECTED by rules   n=  3177  min=0.2000  p10=0.3774  p25=0.4344  p50=0.4660  p75=0.5430  p90=0.6155  max=0.8625

    shipped.aspect               n=   300  min=0.0000  p10=0.5556  p25=0.7333  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.5000  p10=0.5185  p25=0.5625  p50=0.7656  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.2500  p10=0.3889  p25=0.4286  p50=0.5185  p75=0.6333  p90=0.8148  max=1.0000
    shipped.singleton            n=   300  min=0.4000  p10=0.6667  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.2000  p10=0.5000  p25=0.5000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=843 singleton=355 occupancy=1672 blobVsGrid=269 aspect=38
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6327 would sit below 91.6% of currently-rejected candidates and 11.0% of currently-accepted ones.

## HARD

```
  SHIPPED (known-good)           n=   300  min=0.5006  p10=0.6595  p25=0.7153  p50=0.7931  p75=0.8262  p90=0.8722  max=0.9133
  candidates ACCEPTED by rules   n=  1188  min=0.5006  p10=0.6702  p25=0.7262  p50=0.8059  p75=0.8262  p90=0.8722  max=0.9133
  candidates REJECTED by rules   n=  2657  min=0.2000  p10=0.4754  p25=0.4844  p50=0.5486  p75=0.6203  p90=0.6781  max=0.8392

    shipped.aspect               n=   300  min=0.1111  p10=0.4444  p25=0.7222  p50=0.8095  p75=1.0000  p90=1.0000  max=1.0000
    shipped.blobVsGrid           n=   300  min=0.5000  p10=0.6563  p25=0.7656  p50=0.8750  p75=1.0000  p90=1.0000  max=1.0000
    shipped.occupancy            n=   300  min=0.3906  p10=0.4464  p25=0.4464  p50=0.5102  p75=0.5208  p90=0.5952  max=0.8333
    shipped.singleton            n=   300  min=0.5000  p10=0.6667  p25=1.0000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000
    shipped.components           n=   300  min=0.2000  p10=0.5000  p25=0.5000  p50=1.0000  p75=1.0000  p90=1.0000  max=1.0000

  reject reasons: components=1602 singleton=735 occupancy=0 blobVsGrid=232 aspect=88
  generation failures: 0
```

  A floor at SHIPPED p10 = 0.6595 would sit below 88.2% of currently-rejected candidates and 6.0% of currently-accepted ones.

