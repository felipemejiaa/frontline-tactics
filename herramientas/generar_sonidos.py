"""Genera los efectos de sonido del juego (estilo retro, 8 bits).
Uso: python generar_sonidos.py carpeta_destino"""
import sys, wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)
dest = sys.argv[1]


def t(dur):
    return np.arange(int(SR * dur)) / SR


def cuadrada(f, dur, duty=0.5):
    fase = (t(dur) * f) % 1.0
    return np.where(fase < duty, 1.0, -1.0)


def envolvente(n, ataque=0.005, caida=None):
    e = np.ones(n)
    a = max(1, int(SR * ataque))
    e[:a] = np.linspace(0, 1, a)
    if caida is not None:
        e *= np.exp(-np.arange(n) / (SR * caida))
    return e


def ruido(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def pasa_bajos(x, alfa):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alfa * (v - acc)
        y[i] = acc
    return y


def barrido(f0, f1, dur, forma="seno"):
    f = np.linspace(f0, f1, int(SR * dur))
    fase = np.cumsum(f) / SR
    return np.sin(2 * np.pi * fase) if forma == "seno" else np.where(fase % 1 < 0.5, 1.0, -1.0)


def guardar(nombre, x, vol=0.6):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    datos = (x * 32767).astype(np.int16)
    with wave.open(f"{dest}/{nombre}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos.tobytes())


def notas(lista, dur_nota, duty=0.5, caida=0.15):
    partes = []
    for f in lista:
        n = cuadrada(f, dur_nota, duty)
        partes.append(n * envolvente(len(n), caida=caida))
    return np.concatenate(partes)


# --- efectos ---
clic = cuadrada(1400, 0.035, 0.25) * envolvente(int(SR * 0.035), caida=0.012)
guardar("clic", clic, 0.35)

disparo = ruido(0.16) * envolvente(int(SR * 0.16), 0.001, 0.035)
disparo = pasa_bajos(disparo, 0.5) + 0.6 * barrido(220, 60, 0.16) * envolvente(int(SR * 0.16), 0.001, 0.05)
guardar("disparo", disparo, 0.55)

canon = 0.9 * barrido(160, 35, 0.45) * envolvente(int(SR * 0.45), 0.002, 0.14)
canon += pasa_bajos(ruido(0.45), 0.25) * envolvente(int(SR * 0.45), 0.001, 0.08)
guardar("canon", canon, 0.7)

explosion = pasa_bajos(ruido(0.9), 0.12) * envolvente(int(SR * 0.9), 0.002, 0.22)
explosion += 0.7 * barrido(90, 25, 0.9) * envolvente(int(SR * 0.9), 0.002, 0.25)
guardar("explosion", explosion, 0.75)

golpe = pasa_bajos(ruido(0.1), 0.35) * envolvente(int(SR * 0.1), 0.001, 0.025)
guardar("golpe", golpe, 0.5)

paso = cuadrada(180, 0.03, 0.3) * envolvente(int(SR * 0.03), caida=0.01)
guardar("paso", paso, 0.18)

seleccion = notas([880, 1320], 0.05, 0.25, 0.03)
guardar("seleccion", seleccion, 0.3)

compra = notas([988, 1319], 0.07, 0.5, 0.08)
guardar("compra", compra, 0.4)

captura = notas([523, 659, 784, 1047], 0.08, 0.5, 0.1)
guardar("captura", captura, 0.4)

turno = notas([392, 523, 659], 0.09, 0.25, 0.12)
guardar("turno", turno, 0.35)

victoria = notas([523, 659, 784, 1047, 784, 1047], 0.13, 0.5, 0.2)
guardar("victoria", victoria, 0.45)

derrota = notas([659, 587, 523, 392, 330], 0.18, 0.5, 0.25)
guardar("derrota", derrota, 0.45)

print("listo")
