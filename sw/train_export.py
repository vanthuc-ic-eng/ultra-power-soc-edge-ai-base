#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Train 2-layer MLP on MNIST with Data Augmentation (PyTorch)
and export Bit-Exact Log8 / INT8 weights, biases, and test vectors for LA-HWPE.
Network Architecture:
  - Input: 784 (28x28 normalized to [0, 127])
  - Hidden: 64 neurons (ReLU + Requantize >> shift1 to [0, 127])
  - Output: 10 neurons (Logits for classes 0..9 -> Argmax)
Author: Nguyen Van Thuc (24161421)
"""

import gzip
import json
import os
import sys
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
import torchvision.transforms as T

DATA_DIR = "/workspace/projects/pulp_edge_ai_soc/sw/data"
os.makedirs(DATA_DIR, exist_ok=True)

def load_mnist():
    with gzip.open(os.path.join(DATA_DIR, "train-images-idx3-ubyte.gz"), "rb") as f:
        X_train = np.frombuffer(f.read(), np.uint8, offset=16).reshape(-1, 28, 28).astype(np.float32) / 255.0
    with gzip.open(os.path.join(DATA_DIR, "train-labels-idx1-ubyte.gz"), "rb") as f:
        y_train = np.frombuffer(f.read(), np.uint8, offset=8).astype(np.int64)
    with gzip.open(os.path.join(DATA_DIR, "t10k-images-idx3-ubyte.gz"), "rb") as f:
        X_test = np.frombuffer(f.read(), np.uint8, offset=16).reshape(-1, 28, 28).astype(np.float32) / 255.0
    with gzip.open(os.path.join(DATA_DIR, "t10k-labels-idx1-ubyte.gz"), "rb") as f:
        y_test = np.frombuffer(f.read(), np.uint8, offset=8).astype(np.int64)
    return X_train, y_train, X_test, y_test

print("Loading MNIST dataset...")
X_train_np, y_train_np, X_test_np, y_test_np = load_mnist()

# Reproducibility
torch.manual_seed(42)
np.random.seed(42)

# Data Augmentation to make real-time handwritten drawing resilient
train_transform = T.Compose([
    T.RandomAffine(degrees=10, translate=(0.08, 0.08), scale=(0.90, 1.10), shear=5),
])

class AugmentedMNIST(Dataset):
    def __init__(self, images, labels, transform=None):
        self.images = torch.from_numpy(images).unsqueeze(1) # [N, 1, 28, 28]
        self.labels = torch.from_numpy(labels)
        self.transform = transform
        
    def __len__(self):
        return len(self.labels)
        
    def __getitem__(self, idx):
        img = self.images[idx]
        if self.transform:
            img = self.transform(img)
        return img.view(-1), self.labels[idx]

train_dataset = AugmentedMNIST(X_train_np, y_train_np, transform=train_transform)
train_loader = DataLoader(train_dataset, batch_size=128, shuffle=True)

class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(784, 64)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(64, 10)
        
    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.fc2(x)
        return x

model = MLP()
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.003, weight_decay=1e-5)
scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=12)

print("\n--- Training PyTorch MLP with Data Augmentation (12 Epochs) ---")
for epoch in range(12):
    model.train()
    total_loss = 0.0
    for xb, yb in train_loader:
        optimizer.zero_grad()
        out = model(xb)
        loss = criterion(out, yb)
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
    scheduler.step()
    
    # Eval test
    model.eval()
    with torch.no_grad():
        X_test_t = torch.from_numpy(X_test_np).view(-1, 784)
        preds = model(X_test_t).argmax(dim=1).numpy()
        acc = (preds == y_test_np).mean() * 100.0
    print(f"Epoch {epoch+1:2d}/12 | Loss: {total_loss/len(train_loader):.4f} | Test Acc: {acc:.2f}%")

# Save FP32 model checkpoint
torch.save(model.state_dict(), os.path.join(DATA_DIR, "mnist_mlp_pytorch.pt"))
acc_fp = acc

# Extract weights and biases
W1 = model.fc1.weight.detach().cpu().numpy().T # [784, 64]
b1 = model.fc1.bias.detach().cpu().numpy()     # [64]
W2 = model.fc2.weight.detach().cpu().numpy().T # [64, 10]
b2 = model.fc2.bias.detach().cpu().numpy()     # [10]

X_test_flat = X_test_np.reshape(-1, 784)
X_test_int8 = np.clip(np.round(X_test_flat * 127.0), 0, 127).astype(np.int8)

# ============================================================================
# Quantization Pipeline with Exact Mathematical Bias Matching
# ============================================================================
print("\n--- Quantizing to INT8 / Log8 Pre-encoded Formats ---")

# W1 quantization: scale by max absolute value
scale_w1 = 127.0 / np.max(np.abs(W1))
W1_int8 = np.clip(np.round(W1 * scale_w1), -128, 127).astype(np.int8)
# Bias b1 scaled matching (X * W1): scale = 127.0 * scale_w1
scale_b1 = 127.0 * scale_w1
b1_int32 = np.round(b1 * scale_b1).astype(np.int32)

shift1 = 11
print(f"Layer 1 Requantization Shift: {shift1} bits")

# Activation A1 scale:
# In INT: z1 = X_int8 @ W1_int8 + b1_int32 ~= 127.0 * scale_w1 * (X @ W1 + b1)
# a1_int8 = clip(z1 >> shift1, 0, 127)
# Therefore, scale of a1_int8 is:
scale_a1 = (127.0 * scale_w1) / (2.0 ** shift1)

# Layer 2 Quantization
scale_w2 = 127.0 / np.max(np.abs(W2))
W2_int8 = np.clip(np.round(W2 * scale_w2), -128, 127).astype(np.int8)

# In HW: z2 = a1_int8 @ W2_int8 + b2_int32
# Since a1_int8 has scale scale_a1 and W2_int8 has scale scale_w2:
scale_b2 = scale_a1 * scale_w2
b2_int32 = np.round(b2 * scale_b2).astype(np.int32)

print(f"Quantization Scales: scale_w1={scale_w1:.2f}, scale_b1={scale_b1:.2f}, scale_a1={scale_a1:.4f}, scale_w2={scale_w2:.2f}, scale_b2={scale_b2:.2f}")

# ============================================================================
# Accurate lutalm_mul_s8 Software Model
# ============================================================================
lut_low3 = [1, 3, 4, 4, 6, 6, 7, 7]
def enc(x):
    if x < 0:
        mag = (-x) & 0xFF
        sign = 1
    else:
        mag = x & 0xFF
        sign = 0
    zero = (x == 0)
    if zero or mag == 0:
        return sign, zero, 0
    k = mag.bit_length() - 1
    bits = ((mag << (7 - k)) & 0xFF) & 0x7F
    upper = (bits >> 4) & 7
    addr = (bits >> 1) & 7
    low = lut_low3[addr]
    frac = (upper << 3) | low
    return sign, zero, (k << 6) | frac

def mul_s8_approx(a, b, trunc_bits=4):
    sa, za, la = enc(a)
    sb, zb, lb = enc(b)
    log_sum = la + lb
    exp = (log_sum >> 6) & 0xF
    frac_s = log_sum & 0x3F
    mantissa = ((1 << 6) | frac_s)
    shifted = (mantissa << exp) >> 6
    approx_mag = shifted & 0xFFFF
    sign_prod = sa ^ sb
    zero_prod = za | zb
    rem_bits = 16 - trunc_bits
    round_bit = ((approx_mag >> (trunc_bits - 1)) & 1) if trunc_bits > 0 else 0
    raw_trunc = (approx_mag >> trunc_bits) & ((1 << rem_bits) - 1)
    eff_sign = sign_prod and not zero_prod
    eff_round = round_bit and not zero_prod
    eff_raw = 0 if zero_prod else raw_trunc
    carry_in = (not eff_round) if eff_sign else eff_round
    base = (~eff_raw & ((1 << rem_bits) - 1)) if eff_sign else eff_raw
    signed_mag = (base + carry_in) & ((1 << rem_bits) - 1)
    res = signed_mag << trunc_bits
    if res >= 0x8000:
        res -= 0x10000
    return res

lut = np.zeros((256, 256), dtype=np.int16)
for a in range(-128, 128):
    for b in range(-128, 128):
        lut[a + 128, b + 128] = mul_s8_approx(a, b)

# Full Evaluation on 10,000 Test Images
print("\n--- Evaluating Accuracy on 10,000 Test Images ---")

# Exact INT8
z1_exact = (X_test_int8.astype(np.int32) @ W1_int8.astype(np.int32)) + b1_int32
a1_exact = np.clip(np.maximum(0, z1_exact) >> shift1, 0, 127).astype(np.int8)
z2_exact = (a1_exact.astype(np.int32) @ W2_int8.astype(np.int32)) + b2_int32
acc_exact = np.mean(np.argmax(z2_exact, axis=1) == y_test_np) * 100.0

# Approximate HWPE Emulation
N_EVAL = len(X_test_np)
z1_app = np.zeros((N_EVAL, 64), dtype=np.int32)
for i in range(N_EVAL):
    x_idx = X_test_int8[i].astype(np.int32) + 128
    w_idx = W1_int8.astype(np.int32) + 128
    prods = lut[x_idx[:, None], w_idx]
    z1_app[i] = np.sum(prods, axis=0) + b1_int32

a1_app = np.clip(np.maximum(0, z1_app) >> shift1, 0, 127).astype(np.int8)
z2_app = np.zeros((N_EVAL, 10), dtype=np.int32)
for i in range(N_EVAL):
    a_idx = a1_app[i].astype(np.int32) + 128
    w_idx = W2_int8.astype(np.int32) + 128
    prods = lut[a_idx[:, None], w_idx]
    z2_app[i] = np.sum(prods, axis=0) + b2_int32

acc_approx = np.mean(np.argmax(z2_app, axis=1) == y_test_np) * 100.0

print(f"--------------------------------------------------")
print(f"FP32 Baseline Accuracy           : {acc_fp:.2f}%")
print(f"Exact INT8 Quantized Accuracy    : {acc_exact:.2f}%")
print(f"Approximate LA-HWPE Accuracy     : {acc_approx:.2f}%")
print(f"Accuracy Degradation from FP32   : {acc_fp - acc_approx:.2f}%")
print(f"--------------------------------------------------")

# ============================================================================
# Export Hex Files for BRAM Hardware Initialization
# ============================================================================
print("\nExporting Memory (.hex) files for RTL BRAMs...")

W2_padded = np.zeros((64, 12), dtype=np.int8)
W2_padded[:, :10] = W2_int8
b2_padded = np.zeros(12, dtype=np.int32)
b2_padded[:10] = b2_int32

def enc_weight_8b(w):
    w = int(w)
    if w == 0:
        return 0x7F # Reserved zero code (k=7, m=15)
    s = 1 if w < 0 else 0
    mag = abs(w)
    k = mag.bit_length() - 1 # 0 to 6
    sa, za, la = enc(w)
    frac6 = la & 0x3F
    m = min(15, int(round(frac6 / 4.0)))
    code = ((s & 1) << 7) | ((k & 7) << 4) | (m & 0xF)
    return code & 0xFF

weights_hex_path = os.path.join(DATA_DIR, "weights_tcdm.hex")
with open(weights_hex_path, "w") as f:
    # Layer 1 weights (32-bit per line: 4 x 8-bit Log8 pre-encoded weights)
    for g in range(16):
        for k in range(784):
            w0 = enc_weight_8b(W1_int8[k, g*4 + 0])
            w1 = enc_weight_8b(W1_int8[k, g*4 + 1])
            w2 = enc_weight_8b(W1_int8[k, g*4 + 2])
            w3 = enc_weight_8b(W1_int8[k, g*4 + 3])
            word32 = (w3 << 24) | (w2 << 16) | (w1 << 8) | w0
            f.write(f"{word32:08x}\n")
    # Layer 2 weights (32-bit per line)
    for g in range(3):
        for k in range(64):
            w0 = enc_weight_8b(W2_padded[k, g*4 + 0])
            w1 = enc_weight_8b(W2_padded[k, g*4 + 1])
            w2 = enc_weight_8b(W2_padded[k, g*4 + 2])
            w3 = enc_weight_8b(W2_padded[k, g*4 + 3])
            word32 = (w3 << 24) | (w2 << 16) | (w1 << 8) | w0
            f.write(f"{word32:08x}\n")
    # Pad to 16384 words to prevent simulator warnings
    for _ in range(16384 - (16*784 + 3*64)):
        f.write("00000000\n")

# Biases
biases_l1_hex = os.path.join(DATA_DIR, "biases_l1.hex")
with open(biases_l1_hex, "w") as f:
    for b in b1_int32:
        f.write(f"{int(b) & 0xFFFFFFFF:08x}\n")

biases_l2_hex = os.path.join(DATA_DIR, "biases_l2.hex")
with open(biases_l2_hex, "w") as f:
    for b in b2_padded:
        f.write(f"{int(b) & 0xFFFFFFFF:08x}\n")

# Export Sample Test Images (one high-confidence exemplar for each digit 0..9)
samples_hex = os.path.join(DATA_DIR, "sample_images.hex")
sample_indices = []
for digit in range(10):
    candidates = np.where(y_test_np == digit)[0]
    best_idx = candidates[0]
    best_margin = -1e9
    for c_idx in candidates[:50]:
        z1_c = np.sum(lut[X_test_int8[c_idx].astype(np.int32) + 128, W1_int8.astype(np.int32) + 128], axis=0) + b1_int32
        a1_c = np.clip(np.maximum(0, z1_c) >> shift1, 0, 127).astype(np.int8)
        logits_c = np.sum(lut[a1_c.astype(np.int32) + 128, W2_int8.astype(np.int32) + 128], axis=0) + b2_int32
        if np.argmax(logits_c) == digit:
            sorted_l = np.sort(logits_c)
            margin = sorted_l[-1] - sorted_l[-2]
            if margin > best_margin:
                best_margin = margin
                best_idx = c_idx
    sample_indices.append(best_idx)

with open(samples_hex, "w") as f:
    for s_i, idx in enumerate(sample_indices):
        img = X_test_int8[idx] # 784 bytes
        f.write(f"// Image {s_i}: Label = {y_test_np[idx]}, Index = {idx}\n")
        for px in img:
            f.write(f"{int(px) & 0xFF:02x}\n")

# Export dedicated test images for each digit 0..9
for digit in range(10):
    digit_hex_path = os.path.join(DATA_DIR, f"test_image_digit{digit}.hex")
    with open(digit_hex_path, "w") as f:
        img_d = X_test_int8[sample_indices[digit]]
        for px in img_d:
            f.write(f"{int(px) & 0xFF:02x}\n")

# Save summary config
cfg_path = os.path.join(DATA_DIR, "model_config.json")
config = {
    "shift1": shift1,
    "fp32_acc": float(acc_fp),
    "int8_exact_acc": float(acc_exact),
    "approx_acc": float(acc_approx),
    "scale_w1": float(scale_w1),
    "scale_b1": float(scale_b1),
    "scale_a1": float(scale_a1),
    "scale_w2": float(scale_w2),
    "scale_b2": float(scale_b2),
    "sample_labels": [int(y_test_np[idx]) for idx in sample_indices]
}
with open(cfg_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"Exported all files to {DATA_DIR} successfully!")
