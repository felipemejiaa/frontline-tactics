"""Genera los efectos de sonido y la música del juego (estilo retro, 8 bits).
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

# --- música: marcha en La menor, 120 bpm, 8 compases, se repite ---
def frec(nota):
    nombres = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = nombres[nota[0]]
    i = 1
    if len(nota) > 2 or (len(nota) == 2 and nota[1] in "#b"):
        n += 1 if nota[1] == "#" else -1
        i = 2
    octava = int(nota[i:])
    return 440.0 * 2 ** ((n + (octava - 4) * 12) / 12)

negra = 0.5
melodia = [("A4", 1), ("A4", .5), ("B4", .5), ("C5", 1), ("E5", 1),
           ("D5", 1), ("C5", .5), ("B4", .5), ("A4", 2),
           ("C5", 1), ("C5", .5), ("D5", .5), ("E5", 1), ("G5", 1),
           ("F5", 1), ("E5", .5), ("D5", .5), ("E5", 2),
           ("A5", 1), ("G5", .5), ("F5", .5), ("E5", 1), ("C5", 1),
           ("D5", 1), ("B4", .5), ("C5", .5), ("D5", 2),
           ("E5", 1), ("C5", .5), ("B4", .5), ("A4", 1), ("E4", 1),
           ("A4", 1.5), ("B4", .5), ("A4", 2)]
bajo = ["A2", "A2", "F2", "F2", "C3", "C3", "G2", "G2",
        "F2", "F2", "G2", "G2", "A2", "E2", "A2", "A2"]  # una nota por medio compás x2

def pista_melodia():
    partes = []
    for nota, beats in melodia:
        dur = beats * negra
        n = cuadrada(frec(nota), dur, 0.25)
        e = envolvente(len(n), 0.005)
        e[-int(SR * 0.04):] *= np.linspace(1, 0, int(SR * 0.04))
        partes.append(n * e)
    return np.concatenate(partes)

def pista_bajo():
    partes = []
    for nota in bajo:
        for _ in range(4):  # corcheas
            n = cuadrada(frec(nota), negra / 2, 0.5)
            partes.append(n * envolvente(len(n), 0.003, 0.12))
    return np.concatenate(partes)

def pista_bateria(largo):
    x = np.zeros(largo)
    paso_corchea = int(SR * negra / 2)
    for i in range(0, largo - paso_corchea, paso_corchea):
        k = i // paso_corchea
        if k % 4 == 0:  # bombo
            golpe_b = barrido(120, 40, 0.12) * envolvente(int(SR * 0.12), 0.001, 0.04)
            x[i:i + len(golpe_b)] += 0.9 * golpe_b
        elif k % 4 == 2:  # caja
            c = ruido(0.1) * envolvente(int(SR * 0.1), 0.001, 0.03)
            x[i:i + len(c)] += 0.5 * c
        h = ruido(0.03) * envolvente(int(SR * 0.03), 0.001, 0.008)
        x[i:i + len(h)] += 0.15 * h
    return x

m = pista_melodia()
b = pista_bajo()
largo = min(len(m), len(b))
musica = 0.45 * m[:largo] + 0.35 * b[:largo] + 0.5 * pista_bateria(largo)
guardar("musica", musica, 0.5)

# --- golpe crítico: un "zing" metálico agudo y un golpe seco ---
zing = barrido(2400, 1200, 0.18, "cuadrada") * envolvente(int(SR * 0.18), 0.001, 0.06)
punch = pasa_bajos(ruido(0.22), 0.45) * envolvente(int(SR * 0.22), 0.001, 0.05) + barrido(300, 70, 0.22) * envolvente(int(SR * 0.22), 0.001, 0.07)
critico = np.concatenate([0.5 * zing, np.zeros(int(SR * 0.02))])
critico = np.concatenate([critico, punch])
guardar("critico", critico, 0.7)

# --- unidad destruida: explosión grande con tono que cae ---
grande = pasa_bajos(ruido(1.1), 0.18) * envolvente(int(SR * 1.1), 0.002, 0.3)
grande += 0.8 * barrido(140, 20, 1.1) * envolvente(int(SR * 1.1), 0.002, 0.35)
guardar("destruccion", grande, 0.8)

# --- sirena de alarma (antes de la bomba nuclear): sube y baja dos veces ---
f_sirena = np.concatenate([np.linspace(500, 1100, int(SR * 0.45)), np.linspace(1100, 500, int(SR * 0.45))] * 2)
sirena = np.where((np.cumsum(f_sirena) / SR) % 1 < 0.5, 1.0, -1.0) * 0.6
borde = int(SR * 0.05)
sirena[:borde] *= np.linspace(0, 1, borde)
sirena[-borde:] *= np.linspace(1, 0, borde)
guardar("sirena", sirena, 0.45)

# --- bomba nuclear: estallido, retumbo grave y largo ---
dur = 2.8
boom = pasa_bajos(ruido(dur), 0.08) * envolvente(int(SR * dur), 0.003, 0.9)
boom += 1.2 * barrido(90, 18, dur) * envolvente(int(SR * dur), 0.003, 1.0)
golpe_inicial = pasa_bajos(ruido(0.25), 0.6) * envolvente(int(SR * 0.25), 0.001, 0.05)
boom[:len(golpe_inicial)] += 1.5 * golpe_inicial
guardar("nuclear", boom, 0.9)
print("listo")
