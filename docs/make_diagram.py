import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

AZ_BLUE   = "#0078D4"
AZ_DARK   = "#243A5E"
GREY      = "#5B5B66"
LIGHT     = "#F3F7FC"
RED       = "#C0392B"
GREEN     = "#107C41"
PURPLE    = "#5C2D91"
CARD_EDGE = "#D4E3F2"

fig, ax = plt.subplots(figsize=(16, 9), dpi=130)
ax.set_xlim(0, 160)
ax.set_ylim(0, 90)
ax.axis("off")
fig.patch.set_facecolor("white")

ax.text(80, 84, "Modern Observability", ha="center", va="center",
        fontsize=34, fontweight="bold", color=AZ_DARK)
ax.text(80, 78.2, "from telemetry  \u2192  root cause, automatically",
        ha="center", va="center", fontsize=18, color=GREY)

def card(x, y, w, h, title, subtitle, edge=CARD_EDGE, fill=LIGHT,
         tcolor=AZ_DARK, scolor=GREY, title_fs=14, sub_fs=10.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle="round,pad=0.3,rounding_size=1.6",
                 linewidth=2, edgecolor=edge, facecolor=fill))
    ax.text(x + w/2, y + h*0.63, title, ha="center", va="center",
            fontsize=title_fs, fontweight="bold", color=tcolor)
    if subtitle:
        ax.text(x + w/2, y + h*0.27, subtitle, ha="center", va="center",
                fontsize=sub_fs, color=scolor)
    return (x, y, w, h)

def arrow(p1, p2, color=AZ_BLUE, lw=2.6, style="-|>", rad=0, ls="-"):
    ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle=style, mutation_scale=20,
                 linewidth=lw, color=color, linestyle=ls,
                 connectionstyle=f"arc3,rad={rad}"))

top_y = 52
W, H = 30, 14

card(6,  top_y, W, H, "Web App", "Flask on App Service\n/error  ->  500", edge="#E6C9C4")
ax.text(6 + W/2, top_y - 3.4, "deliberately broken endpoint", ha="center",
        fontsize=9.5, color=RED, style="italic")
card(44, top_y, W, H, "Telemetry", "Application Insights\n+ Log Analytics (KQL)")
card(82, top_y, W, H, "Alerts", "Metric alert  +  Log-query alert", edge="#F2E2C4")
card(120, top_y, W+4, H+3, "Observability Agent",
     "autonomous AI\ncorrelate  -  investigate", edge="#D9CBEA",
     fill="#F4EEFB", tcolor=PURPLE, title_fs=15)

arrow((6+W,  top_y+H/2), (44,  top_y+H/2))
arrow((44+W, top_y+H/2), (82,  top_y+H/2))
arrow((82+W, top_y+H/2), (120, top_y+H/2))
ax.text(38.5, top_y+H/2+2.6, "OpenTelemetry", ha="center", fontsize=9, color=GREY)
ax.text(76.5, top_y+H/2+2.6, "thresholds", ha="center", fontsize=9, color=GREY)
ax.text(114.5, top_y+H/2+2.6, "watches", ha="center", fontsize=9, color=GREY)

out_y = 26
card(108, out_y, 46, 16, "Root-caused Issue",
     "names the failing endpoint\n+ the underlying exception",
     edge="#BFE3CC", fill="#EAF6EF", tcolor=GREEN, title_fs=15)
arrow((120+(W+4)/2, top_y), (108+23, out_y+16), color=PURPLE, lw=2.8)
ax.text(141, top_y-4.5, "creates", ha="center", fontsize=10, color=PURPLE, fontweight="bold")

hil_y = 26
card(6, hil_y, 40, 16, "Human-in-the-loop",
     "manually Investigate any alert\naccept / reject findings",
     edge="#CBD6E2", fill="#EEF3F8", title_fs=14)
arrow((82, top_y+2), (40, hil_y+16), color=GREY, lw=2.2, rad=-0.25, ls=(0,(5,4)))
ax.text(58, 46, "you stay in control", ha="center", fontsize=10, color=GREY, style="italic")

ax.add_patch(FancyBboxPatch((6, 6), 148, 11,
             boxstyle="round,pad=0.3,rounding_size=1.4",
             linewidth=0, facecolor="#0E2440"))
ax.text(12, 11.5, "BEFORE", ha="left", va="center", fontsize=12,
        fontweight="bold", color="#7FB2E5")
ax.text(30, 11.5, "30 min of tab-hopping across logs, metrics & traces",
        ha="left", va="center", fontsize=12.5, color="white")
ax.text(96, 11.5, "AFTER", ha="left", va="center", fontsize=12,
        fontweight="bold", color="#76D7A0")
ax.text(110, 11.5, "start at the answer, not the haystack",
        ha="left", va="center", fontsize=12.5, color="white")

ax.text(80, 1.8, "github.com/lshaible/azure-observability-agent-demo  -  Azure Monitor Observability Agent (preview)",
        ha="center", va="center", fontsize=11, color=GREY)

plt.tight_layout()
out = r"C:\Observability\obs-demo\docs\observability-agent-architecture.png"
plt.savefig(out, dpi=130, bbox_inches="tight", facecolor="white", pad_inches=0.25)
print("saved", out)
