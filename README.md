# biomat-char-agent

**An AI agent for biomaterial characterization that only reports numbers it actually computed.**

`biomat-char-agent` reads raw files straight from lab instruments (FTIR, XRD, rheometer, tensile tester, TGA,
swelling and gel-fraction sheets). It computes the results, makes publication-ready figures and Origin-ready tables,
and lets Claude write the results text from those numbers. It does not guess peak assignments or make up values,
and it never invents references.

It was built to replace a workflow where a chatbot "interpreted" spectra from screenshots. That workflow produced
confident claims the data did not support. This project uses the opposite approach. Code measures, the model explains,
and every claim is checked against the control sample.

<p align="center">
  <img src="docs/images/example_ftir_all.png" width="48%" alt="FTIR overlay">
  <img src="docs/images/example_rheology_frequency_sweep.png" width="48%" alt="Rheology frequency sweep">
</p>
<p align="center"><sub>Example output on mock data. Right: rheometer points affected by instrument inertia (grey ×) are detected and excluded automatically.</sub></p>

---

## Why it exists

Typical characterization write-ups go wrong in a few predictable ways, and each one has a guard here:

| Common mistake | What the agent does instead |
|---|---|
| "The Si–O–Si peak appeared, so silica was incorporated", when the control has a band there too | Band-area ratios **against the control**, normalised to an internal reference band |
| Assigning a band to a group that absorbs outside the scanned range (e.g. Zn–O below a 650 cm⁻¹ ATR cutoff) | The band table records scan limits and overlaps, and every assignment carries a caution field |
| Reporting rheometer points distorted by inertia or non-linearity | Points with phase outside 0–90°, high harmonic distortion or off-target strain are excluded **with a stated reason** |
| Calling mass gain from an already-swollen gel a "swelling ratio" | Flagged unless the dry mass is given |
| Counting the same test twice because it was exported under two names | Byte-identical files are detected and loaded once |
| Made-up citations | Not possible: the agent writes `[ref needed: …]` instead |

## Features

| Technique | Reads | Computes |
|---|---|---|
| **FTIR** | PerkinElmer `.asc`, Thermo OMNIC `.spa`, CSV, Origin `.xlsx` | absorbance, baseline, peak picking, band assignment with overlap warnings, band ratios vs control |
| **XRD** | PANalytical `.xrdml`, HighScore `.txt`, `.xlsx` | amorphous halo, peaks, d-spacing, FWHM, Scherrer size, relative crystallinity, ZnO reference matching |
| **Rheology** | Malvern Kinexus CSV (decimal comma), generic G′/G″ tables | quality screening, G′, G″, tan δ at 1 Hz, power-law exponent, crossover |
| **Tensile** | testing-machine `.xls` (Excel 2003 XML), `.xlsx` | UTS, elongation at break, modulus (with gauge length), mean ± SD, representative curve |
| **TGA / DTG** | CSV / XLSX / TXT (English or Turkish headers) | T5 %, T10 %, T50 %, DTG peaks, moisture loss, residue |
| **Swelling** | workbook, one sheet per sample | swelling ratio, equilibrium, rate constant, t90 |
| **Gel fraction** | workbook | gel fraction, cross-check against reported values |
| **SEM** | `.tif` | labelled multi-panel figures |

Outputs for every project are CSV tables, 600 dpi figures (white background, no gridlines, inverted wavenumber axis)
and Excel sheets formatted for OriginPro import.

## Quick start

```bash
git clone https://github.com/<you>/biomat-char-agent.git
cd biomat-char-agent
pip install -e ".[agent,dev]"

pytest                                              # runs on mock data, no lab files needed
biomatchar benchmark --scenario messy --seed 3      # score the pipeline against known answers
```

Run it on your own data:

```bash
biomatchar projects                                 # list configured studies
biomatchar inventory --config thiol_yne_ha_hydrogel # what files were found (and duplicates)
biomatchar run --config thiol_yne_ha_hydrogel       # tables, figures, Origin sheets -> reports/<project>/
```

Ask the agent (needs an [Anthropic API key](https://docs.claude.com/en/api/overview)):

```bash
export ANTHROPIC_API_KEY=sk-...
biomatchar ask "Compare the rheology of the PLA series and say which differences are real" --config thiol_yne_ha_hydrogel
biomatchar ask "nSiA serisinin FTIR sonuçlarını kontrolle karşılaştırarak 110 kelimelik bir paragraf yaz"
```

Or call any analysis tool directly, without the API:

```bash
biomatchar tool rheology_summary --config thiol_yne_ha_hydrogel
biomatchar tool ftir_band_ratios
```

## Tested against ground truth

`biomatchar mock` writes a complete fake study **in real instrument formats** with known answers for every number.
`biomatchar benchmark` runs the pipeline on it and scores each result.

- **clean**: tidy files
- **messy**: noise, sloping baselines, duplicate exports, broken XML, decimal commas, Turkish headers,
  rheometer inertia artefacts, 50 % harmonic distortion, an empty data sheet

Current status: **44/44 checks (clean) and 51/51 checks (messy) pass across seeds.** The messy benchmark already
caught one real bug: an encoding error that garbled Turkish TGA headers.

## Configured studies

| Config | Material system | Techniques |
|---|---|---|
| `pva_sa_gel_nanosilica` | PVA / sodium alginate / gelatin films with nano-silica, silica aerogel and Zn-doped aerogel (10 samples) | FTIR, XRD, tensile, (TGA, SEM) |
| `thiol_yne_ha_hydrogel` | Thiol-yne photo-crosslinked PEG hydrogels with PLA-propargyl and hyaluronic acid (nerve-tissue scaffold) | FTIR, rheology, swelling, gel fraction |

Findings from the real data are in [`docs/findings_from_data.md`](docs/findings_from_data.md) and
[`docs/findings_thiol_yne.md`](docs/findings_thiol_yne.md). Progress, open questions and the roadmap are in
[`WORKLOG.txt`](WORKLOG.txt).

## Add your own study

1. Copy a file in `configs/` and edit the sample table. Give each sample `aliases` (regex) that match your file,
   column or sheet names, for example `"H_10PLA"`, `"yuzde 10\\b"` or `"^10%$"`.
2. Put instrument files in `data/<project>/raw/<technique>/` without renaming them.
3. `biomatchar run --config <your_config>`.

New material systems get their own FTIR band table in `knowledge/`.

## How the agent works

```
your question ──► Claude ──► tool call (e.g. rheology_summary) ──► Python reads raw files, computes, screens
                    ▲                                                        │
                    └──────────── numbers + caution notes ◄──────────────────┘
```

Rules built into the agent (`src/biomatchar/agent/run.py`):

- Every statement must rest on numbers returned by a tool in that conversation.
- A band or peak that also appears in the control is not evidence for the additive.
- Caution notes (band overlaps, excluded points, unconfirmed sample maps) must be respected.
- No invented citations.

## Project layout

```
configs/                 one YAML per study: samples, aliases, methods, assumptions
knowledge/               FTIR band tables per material system
src/biomatchar/
  io/                    instrument readers (asc, spa, xrdml, HighScore, SpreadsheetML, Kinexus, ...)
  analysis/              ftir, xrd, tensile, tga, rheology, hydrogel
  pipeline.py            run everything for one study
  mock.py, benchmark.py  fake studies with ground truth + scoring
  agent/                 Claude tool-use loop and tool definitions
  cli.py                 `biomatchar` command
docs/                    findings, project history, example images
tests/                   pytest suite
data/, reports/          local only (git-ignored)
```

## Data privacy

`data/` and `reports/` are git-ignored, so raw measurements never leave your machine unless you choose to publish them.
Example images in this README come from mock data.

## Roadmap

Swelling models with a lag phase (Peppas / sigmoidal), FTIR degree of conversion against a monomer reference,
amplitude and time sweeps (gel point), SEM pore-size analysis, ANOVA / Tukey between samples, a verified-reference
library for citations, and Word / Google Docs report export. Details are in [`WORKLOG.txt`](WORKLOG.txt).

## Author

Ali Özmen, biomedical engineer (MSc Biomaterial Engineering).
Built with Claude.
