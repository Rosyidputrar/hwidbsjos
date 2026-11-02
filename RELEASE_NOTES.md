<!-- Catatan rilis: tulis hanya perubahan yang dirasakan pengguna, tanpa nama repo/branch/PR. Isi file ini dipakai sebagai body rilis. -->

## Bahasa Indonesia

- Rynex kini bring your own provider: tidak ada lagi provider bawaan yang terkunci. Hubungkan provider dengan masuk memakai akun (Anthropic, OpenAI, Gemini, OpenRouter, dan lainnya), menempel kunci API, atau menambahkan endpoint kustom apa pun yang kompatibel — Ollama lokal, gateway kantor, atau servermu sendiri. Layarnya ada di Pengaturan → Model & provider.
- Sistem kredit hilang. Semua biaya kini dihitung dari tarif tiap model sendiri dan ditampilkan dalam USD: di layar Pemakaian, di catatan kaki tiap balasan, di panel subagent, dan di batas harian serta batas subagent (yang kini juga dalam USD).
- Fitur buat gambar dan pencarian web lewat model dihapus, karena keduanya bergantung pada layanan tertentu. Pencarian web tetap jalan lewat Search1API, TinyFish, Brave, Tavily, dan DuckDuckGo.
- Endpoint kustom kini bisa diberi harga input dan output (USD per 1 juta token), supaya biaya dan batas harian bekerja di endpoint sendiri. Tanpa harga, biayanya tampil sebagai tidak diketahui.
- Tampilan mengikuti desain Rynex: aksen lime, kartu dan kolom berbingkai, serta navigasi bawah dengan tombol buat.
- Kunci API provider tidak lagi diteruskan ke git dan server MCP, dan perintah yang menyebut kunci itu kini meminta persetujuan.
- Nama, ikon, dan identitas aplikasi diperbarui menjadi Rynex (paket com.airynex.agent). Folder data lama di server otomatis berganti nama saat pertama dijalankan, jadi sesi dan pengaturanmu tetap ada.

## English

- Rynex is now bring-your-own-provider: there is no locked built-in provider anymore. Connect a provider by signing in with an account (Anthropic, OpenAI, Gemini, OpenRouter and more), pasting an API key, or adding any compatible custom endpoint — a local Ollama, a company gateway, or your own server. Find it in Settings → Models & providers.
- The credit system is gone. Every cost is now priced from each model's own rates and shown in USD: on the Usage screen, in each reply's footer, in the subagent panel, and in the daily and subagent limits (also in USD now).
- Image generation and model-backed web search are removed, because both depended on one specific service. Web search still runs through Search1API, TinyFish, Brave, Tavily and DuckDuckGo.
- A custom endpoint can now be given input and output prices (USD per million tokens), so cost and the daily limit work on your own endpoint. Without prices the cost shows as unknown.
- The look follows the Rynex design: lime accent, outlined cards and fields, and the docked navigation bar with the create button.
- Provider API keys are no longer passed on to git and MCP servers, and a command that names such a key now asks first.
- The app's name, icon and identity are now Rynex (package com.airynex.agent). On a server, the old data folder is renamed automatically on first run, so your sessions and settings carry over.
