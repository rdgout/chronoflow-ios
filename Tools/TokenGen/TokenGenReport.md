# TokenGen report

Source: `_design/canvas/ds/chronoflow/tokens.json`. OKLCH → OKLab → linear Display P3 → clip → sRGB transfer curve. Conversion matrices follow [CSS Color 4](https://www.w3.org/TR/css-color-4/#color-conversion-code). Hex values are clipped sRGB.

| Token | Light sRGB | Light P3 | Dark sRGB | Dark P3 |
|---|---|---|---|---|
| skyTop | #1F285A | 0.1284753585 0.1565420056 0.3411446479 | #06091C | 0.0259695822 0.0360074373 0.1041462153 |
| skyMid | #4D427F | 0.2951486928 0.2590667942 0.4835849939 | #221A40 | 0.1281055407 0.1029479048 0.2428664457 |
| skyHorizon | #EB9666 | 0.8732523385 0.6048251546 0.4334483478 | #AA5830 | 0.6228083277 0.3603616514 0.2227518339 |
| skyTitle | #F4F9FF | 0.9589967179 0.9762308201 0.9981208152 | #E5ECF6 | 0.9039299719 0.9230007624 0.9590599670 |
| skyCopy | #121932 | 0.0746269467 0.0960047157 0.1879246112 | #E5ECF6 | 0.9039299719 0.9230007624 0.9590599670 |
| skyCopyBackground | #F3F7FC α0.9 | 0.9554061387 0.9691773029 0.9866671639 | #0A0E1F α0.9 | 0.0426907083 0.0547508757 0.1152662036 |
| dawn | #E78A45 | 0.8542512390 0.5599361895 0.3257756868 | #F2AD73 | 0.9082625891 0.6882337800 0.4860896207 |
| dawnForeground | #2D1205 | 0.1627311436 0.0755993915 0.0303297406 | #101428 | 0.0652879355 0.0798151287 0.1517375932 |
| background | #F3F7FC | 0.9554061387 0.9691773029 0.9866671639 | #0A0E1F | 0.0426907083 0.0547508757 0.1152662036 |

Light sky: 17 stops, including exact mid 0.55; encoded Display P3 channel interpolation checked at 1001 points to ±1/255.

Dark sky: 17 stops, including exact mid 0.6; encoded Display P3 channel interpolation checked at 1001 points to ±1/255.
