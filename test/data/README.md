# Experiment data sets

One folder per physical setup (or synthetic scene). The folder **is** the
dataset: raw captures, your measured ground truth, photos/videos of the
setup, and regenerable analysis, all together and all committed.

```
experiments/YYYY-MM-DD_slug/
    experiment.json      manifest: kind (hardware|synthetic), capture params,
                         ground_truth.objects[].range_m (YOUR measured ranges),
                         list of captures
    notes.md             free-form lab notes
    raw/capture_NNN.pdm  exact FPGA dumps, 1 byte/PDM period, bit k = mic k+1
    media/               photos + videos of the setup (drop them in manually)
    analysis/            plots + results.json - regenerable, safe to delete
```

## Recording from the PCB

Set up the scene, measure the object distance(s) with a tape measure, then:

```sh
.venv/bin/python host/capture_mic.py --experiment wall-1m --truth 1.00 \
    --desc "cardboard box, boresight, 1.00 m" --num 5
```

That creates `experiments/<today>_wall-1m/`, fires 5 pings, stores each dump,
and runs the analysis. Re-running with the same slug appends more captures to
the same folder. Then drop your setup photos/videos into `media/` and commit
the folder. (If videos get large, consider `git lfs track "experiments/**/media/*"`.)

## Synthetic scenes (no hardware)

```sh
.venv/bin/python host/make_synthetic.py --range 0.6 --az 15 --range 1.4 --az -10 \
    --name two-objects
```

Same folder format, exact ground truth - used by CI and for algorithm work
away from the bench.

## Re-analysis + tests

```sh
.venv/bin/python host/analyze_experiment.py --all   # rebuild all analysis/
.venv/bin/python -m pytest                          # incl. detector-vs-truth
```

`tests/test_experiment_data.py` automatically turns **every capture with
ground truth in this directory** into a test case: the detector must find
each true object range (±6 cm synthetic, ±15 cm hardware). Adding a new
experiment folder grows the regression suite by itself.

Analysis reports each object as range **and azimuth** (delay-and-sum
beamforming; `analysis/bscan_NNN.png` shows the az×range map). If you also
measure an object's bearing on the bench, record it as `azimuth_deg` next
to `range_m` in the manifest's ground truth (positive = +x side of the
board, toward MK4).
