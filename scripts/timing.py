import math
import matplotlib.pyplot as plt
import numpy as np


speed_ratio = 25 / 3
# speed_ratio = 8.5


def get_from_usb(d, clk_offset=0):
    l = math.floor(len(d) * speed_ratio)
    idx = np.array([int((i + clk_offset) // speed_ratio) for i in range(l)])
    return np.array(d)[idx]


def plot_usb(ax, d):
    x = range(len(d) + 1)
    px = np.repeat(x, 2)[1:-1] * speed_ratio
    pd = np.repeat(d, 2)
    ax.plot(px, pd, label="USB")


def plot_waveform(ax, w, n=1, clk_offset=0):
    x = range(len(w) + 1)
    px = np.repeat(x, 2)[1:-1] + clk_offset
    pw = np.repeat(w, 2)
    ax.plot(px, pw, label=f"Wave {n}")


usb = [i % 2 for i in range(11)]

fig, axs = plt.subplots(2, 3)
n_plots = 6
for i in range(n_plots):
    ax = axs[i // 3, i % 3]

    plot_usb(ax, usb)

    samples = get_from_usb(usb, clk_offset=i / n_plots)
    plot_waveform(ax, samples, n=i, clk_offset=i / n_plots)

    wave = []
    found = False
    count = 4
    for s in samples:
        if found:
            count = 7 if count == 0 else count - 1
        elif s:
            found = True
        wave.append(1 if count == 0 else 0)
    plot_waveform(ax, wave, n=i, clk_offset=i / n_plots)

    # ax.legend()

plt.show()
