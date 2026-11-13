# Repetition penalty comparison

Date: 2026-11-13

Original ASR text is passed directly to the model. No semantic preprocessing or rule-generated replacement is used. Only repetition penalty changed from 1.05 to 1.0; temperature remains 0.15. Input tags, assistant prefill, and disabled thinking were already present. Each configuration was sampled once; these observations are not a statistical quality estimate.

Input: 今天下午三点钟，啊不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。

## Results

| Penalty | Quantization | Level | Seconds | Actual output |
| --- | --- | --- | --- | --- |
| 1.05 | int5 | Light | 3.52 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。 |
| 1.05 | int5 | Moderate | 3.60 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望各位家长能够准时到。 |
| 1.05 | int5 | Deep | 3.31 | 今天下午三点钟，地点在三帆中学明远校区，召开家长会，请各位家长准时到场。 |
| 1.05 | int5 | Professional rewrite | 3.75 | 1. 时间：下午两点钟；地点：三帆中学明远校区；事项：召开家长会；要求：家长需准时到场。 |
| 1.05 | int8 | Light | 3.22 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃，开家长会。希望各位家长能够准时到。 |
| 1.05 | int8 | Moderate | 3.62 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，开家长会。希望各位家长能准时到。 |
| 1.05 | int8 | Deep | 3.32 | 今天下午三点钟，在三帆中学明远校区召开家长会，希望各位家长能够准时到场。 |
| 1.05 | int8 | Professional rewrite | 3.66 | 下午三点钟，地点在三帆中学明远校区，召开家长会，请家长准时到场。 |
| 1.00 | int5 | Light | 3.20 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。 |
| 1.00 | int5 | Moderate | 3.63 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望各位家长能够准时到。 |
| 1.00 | int5 | Deep | 3.37 | 今天下午三点钟，在三帆中学明远校区召开家长会，希望各位家长能够准时到场。 |
| 1.00 | int5 | Professional rewrite | 3.64 | 下午三点钟，即两点钟，在三帆中学明远校区召开家长会。希望各位家长能够准时到场。 |
| 1.00 | int8 | Light | 3.19 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望各位家长能够准时到。 |
| 1.00 | int8 | Moderate | 3.52 | 今天下午三点钟，不对，是两点钟，在三帆中学的明远校区，开家长会。希望各位家长能够准时到。 |
| 1.00 | int8 | Deep | 3.29 | 今天下午三点钟，在三帆中学明远校区召开家长会，希望各位家长能够准时到场。 |
| 1.00 | int8 | Professional rewrite | 3.70 | 下午三点钟，地点在三帆中学明远校区，召开家长会。希望各位家长能够准时到场。 |

## Interpretation

- Disabling the penalty avoids penalizing source-word reuse: the dependency sampler passes prompt tokens plus generated tokens as repetition history. It does not fix correction handling in this sample.
- Both quantizations still fail the fixed parent-meeting quality regression at penalty 1.0. Moderate retains the correction history; Deep selects the superseded time; Professional rewrite also mishandles time and omits the relative date.
- All 16 outputs pass the generic safety check. That check is not a semantic fidelity guarantee.
- Light intentionally retains correction history, but still fails to remove some filler words; passing its fact assertions does not imply complete tier compliance.
- No system prompt changes were made in this experiment. No evidence supports an 80% improvement claim or an INT8 quality advantage from this sample.
- The parameter change is an editing configuration correction, not a demonstrated quality or latency fix. Further prompt comparisons need diverse held-out inputs and repeated trials; do not add example-specific source rewrites.
