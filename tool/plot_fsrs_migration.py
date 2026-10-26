"""Plot the CSV emitted by fsrs_migration_curve.dart; requires matplotlib."""
import csv
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1] / 'docs/evidence/gul-508'
rows = list(csv.DictReader((root / 'due-curve.csv').open()))
x = list(range(len(rows)))
fig, axes = plt.subplots(2, 1, figsize=(11, 5), sharex=True, height_ratios=[3, 1])
axes[0].plot(x, [int(r['before']) for r in rows], label='Before (SM-2)', linewidth=3, color='#2563eb')
axes[0].plot(x, [int(r['after']) for r in rows], label='After (FSRS initialization)', linestyle='--', color='#f97316')
axes[0].set(ylabel='Cards due that day', title='360 legacy cards: due dates preserved exactly')
axes[0].legend()
axes[1].plot(x, [int(r['delta']) for r in rows], color='#16a34a')
axes[1].set(ylabel='Delta', ylim=(-1, 1))
axes[1].set_xticks(x[::14], [r['date'] for r in rows[::14]], rotation=20)
for axis in axes:
    axis.grid(alpha=.2)
fig.tight_layout()
fig.savefig(root / 'due-curve.png', dpi=160)
