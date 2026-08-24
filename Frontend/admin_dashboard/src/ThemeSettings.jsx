import { useEffect, useMemo, useState } from 'react'

import { getThemeSettings, updateThemeSettings } from './api.js'

const DEFAULT_THEME = Object.freeze({
  background: '#101214',
  surface: '#1A1D21',
  surface_soft: '#24282E',
  text_primary: '#F8FAFC',
  text_muted: '#9CA3AF',
  accent: '#19D37E',
  warning: '#FFC857',
  danger: '#FF5D5D',
})

const colorFields = [
  {
    key: 'background',
    label: 'Latar utama',
    description: 'Warna dasar seluruh layar vending machine.',
  },
  {
    key: 'text_primary',
    label: 'Teks utama',
    description: 'Judul, nama produk, dan informasi penting.',
  },
  {
    key: 'text_muted',
    label: 'Teks sekunder',
    description: 'Keterangan, harga, dan informasi pendukung.',
  },
  {
    key: 'accent',
    label: 'Aksen utama',
    description: 'Tombol, kode slot, total, dan penanda aktif.',
  },
  {
    key: 'warning',
    label: 'Sorotan',
    description: 'Badge jumlah, proses menunggu, dan perhatian.',
  },
  {
    key: 'danger',
    label: 'Bahaya',
    description: 'Stok habis, pembatalan, dan pesan kegagalan.',
  },
]

const hexPattern = /^#[0-9A-F]{6}$/

function shiftedHex(hex, offsets) {
  if (!hexPattern.test(hex)) return null
  const channels = [1, 3, 5].map((index) => Number.parseInt(hex.slice(index, index + 2), 16))
  const perceivedBrightness =
    channels[0] * 0.299 + channels[1] * 0.587 + channels[2] * 0.114
  const direction = perceivedBrightness > 180 ? -1 : 1
  return `#${channels
    .map((channel, index) =>
      Math.max(0, Math.min(255, channel + offsets[index] * direction))
        .toString(16)
        .padStart(2, '0'),
    )
    .join('')}`.toUpperCase()
}

function withDerivedSurfaces(theme) {
  const surface = shiftedHex(theme.background, [10, 11, 13])
  const surfaceSoft = shiftedHex(theme.background, [20, 22, 26])
  if (!surface || !surfaceSoft) return theme
  return { ...theme, surface, surface_soft: surfaceSoft }
}

function editableTheme(theme) {
  return withDerivedSurfaces(
    Object.fromEntries(
      Object.keys(DEFAULT_THEME).map((key) => [key, theme?.[key] || DEFAULT_THEME[key]]),
    ),
  )
}

function normalizeHex(value) {
  const cleaned = value.trim().toUpperCase()
  return cleaned.startsWith('#') ? cleaned : `#${cleaned}`
}

function previewStyle(theme) {
  return {
    '--vm-background': theme.background,
    '--vm-surface': theme.surface,
    '--vm-surface-soft': theme.surface_soft,
    '--vm-text-primary': theme.text_primary,
    '--vm-text-muted': theme.text_muted,
    '--vm-accent': theme.accent,
    '--vm-warning': theme.warning,
    '--vm-danger': theme.danger,
  }
}

export default function ThemeSettings() {
  const [savedTheme, setSavedTheme] = useState(DEFAULT_THEME)
  const [draftTheme, setDraftTheme] = useState(DEFAULT_THEME)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  useEffect(() => {
    let ignored = false
    getThemeSettings()
      .then((theme) => {
        if (ignored) return
        const editable = editableTheme(theme)
        setSavedTheme(editable)
        setDraftTheme(editable)
      })
      .catch((requestError) => {
        if (!ignored) setError(requestError.message)
      })
      .finally(() => {
        if (!ignored) setLoading(false)
      })

    return () => {
      ignored = true
    }
  }, [])

  const invalidFields = useMemo(
    () =>
      colorFields
        .filter(({ key }) => !hexPattern.test(draftTheme[key]))
        .map(({ label }) => label),
    [draftTheme],
  )
  const hasChanges = colorFields.some(
    ({ key }) => draftTheme[key] !== savedTheme[key],
  )

  function changeColor(key, value) {
    setDraftTheme((current) => {
      const updated = { ...current, [key]: value.toUpperCase() }
      return key === 'background' ? withDerivedSurfaces(updated) : updated
    })
    setError('')
    setNotice('')
  }

  function finishHexInput(key) {
    setDraftTheme((current) => {
      const updated = { ...current, [key]: normalizeHex(current[key]) }
      return key === 'background' ? withDerivedSurfaces(updated) : updated
    })
  }

  async function saveTheme() {
    if (invalidFields.length > 0) {
      setError(`Format warna belum valid: ${invalidFields.join(', ')}.`)
      return
    }

    setSaving(true)
    setError('')
    setNotice('')
    try {
      const updated = editableTheme(
        await updateThemeSettings(withDerivedSurfaces(draftTheme)),
      )
      setSavedTheme(updated)
      setDraftTheme(updated)
      setNotice('Palet berhasil diterapkan ke vending machine.')
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      setSaving(false)
    }
  }

  function resetDraft() {
    setDraftTheme(DEFAULT_THEME)
    setError('')
    setNotice('Palet bawaan siap dipreview. Tekan Simpan & Terapkan untuk menggunakannya.')
  }

  return (
    <section className="theme-settings" id="theme-panel">
      <div className="theme-page-heading">
        <div>
          <p className="section-kicker">TAMPILAN MESIN</p>
          <h2>Pengaturan palet warna</h2>
          <p className="panel-description">
            Atur warna berdasarkan fungsinya. Preview menu diperbarui langsung,
            sedangkan layar mesin berubah setelah palet disimpan.
          </p>
        </div>
        <span className={`change-indicator ${hasChanges ? 'change-indicator--active' : ''}`}>
          {hasChanges ? 'Ada perubahan' : 'Tersimpan'}
        </span>
      </div>

      {error && <div className="alert alert--error" role="alert">{error}</div>}
      {notice && <div className="alert alert--success" role="status">{notice}</div>}

      <div className="theme-workspace">
        <section className="panel palette-editor" aria-label="Editor warna">
          <div className="palette-editor-heading">
            <div>
              <h3>Warna desain</h3>
              <p>
                Gunakan pemilih warna atau masukkan kode HEX. Warna pemisah
                dibuat otomatis dari latar utama.
              </p>
            </div>
            <button
              className="button button--ghost"
              disabled={loading || saving}
              onClick={resetDraft}
              type="button"
            >
              Reset bawaan
            </button>
          </div>

          {loading ? (
            <div className="palette-loading">Mengambil palet tersimpan...</div>
          ) : (
            <div className="color-field-grid">
              {colorFields.map((field) => {
                const valid = hexPattern.test(draftTheme[field.key])
                return (
                  <label className="color-field" key={field.key}>
                    <span className="color-field-copy">
                      <strong>{field.label}</strong>
                      <small>{field.description}</small>
                    </span>
                    <span className="color-input-group">
                      <input
                        aria-label={`Pilih ${field.label}`}
                        className="color-swatch-input"
                        disabled={saving}
                        onChange={(event) => changeColor(field.key, event.target.value)}
                        type="color"
                        value={valid ? draftTheme[field.key] : DEFAULT_THEME[field.key]}
                      />
                      <input
                        aria-invalid={!valid}
                        aria-label={`Kode HEX ${field.label}`}
                        className={`hex-input ${valid ? '' : 'hex-input--invalid'}`}
                        disabled={saving}
                        maxLength={7}
                        onBlur={() => finishHexInput(field.key)}
                        onChange={(event) => changeColor(field.key, event.target.value)}
                        spellCheck="false"
                        value={draftTheme[field.key]}
                      />
                    </span>
                  </label>
                )
              })}
            </div>
          )}

          <div className="palette-actions">
            <button
              className="button button--ghost"
              disabled={!hasChanges || saving}
              onClick={() => {
                setDraftTheme(savedTheme)
                setError('')
                setNotice('Perubahan yang belum disimpan dibatalkan.')
              }}
              type="button"
            >
              Batalkan perubahan
            </button>
            <button
              className="button button--primary save-theme-button"
              disabled={loading || saving || !hasChanges || invalidFields.length > 0}
              onClick={saveTheme}
              type="button"
            >
              {saving ? 'Menerapkan...' : 'Simpan & Terapkan'}
            </button>
          </div>
        </section>

        <section className="panel preview-panel" aria-label="Preview menu vending machine">
          <div className="preview-heading">
            <div>
              <p className="section-kicker">PREVIEW LANGSUNG</p>
              <h3>Tampilan menu</h3>
            </div>
            <span>9:16</span>
          </div>
          <VendingMenuPreview theme={draftTheme} />
          <p className="preview-note">
            Preview mengikuti menu Flutter tanpa latar kartu produk; foto dan
            ukuran layar sebenarnya tetap mengikuti perangkat.
          </p>
        </section>
      </div>
    </section>
  )
}

function VendingMenuPreview({ theme }) {
  const products = [
    { slot: '01', name: 'Keripik', price: 'Rp 8.000', icon: '●', selected: 2 },
    { slot: '02', name: 'Biskuit', price: 'Rp 10.000', icon: '◆' },
    { slot: '03', name: 'Minuman', price: 'Rp 12.000', icon: '▰' },
    { slot: '04', name: 'Kosong', price: 'Stok habis', icon: '—', disabled: true },
    { slot: '05', name: 'Cokelat', price: 'Rp 9.000', icon: '■' },
    { slot: '06', name: 'Permen', price: 'Rp 6.000', icon: '●' },
  ]

  return (
    <div className="vending-preview" style={previewStyle(theme)}>
      <div className="vending-preview-topbar">
        <div>
          <span>SMART VENDING</span>
          <strong>PILIH PRODUK</strong>
        </div>
        <button aria-label="Tutup preview" tabIndex="-1" type="button">×</button>
      </div>
      <div className="preview-products">
        {products.map((product) => (
          <article
            className={`preview-product ${product.disabled ? 'preview-product--disabled' : ''}`}
            key={product.slot}
          >
            {product.selected && <b className="preview-quantity">×{product.selected}</b>}
            <i>{product.icon}</i>
            <strong>{product.name}</strong>
            <small>{product.price}</small>
            <span>{product.slot}</span>
          </article>
        ))}
      </div>
      <div className="preview-cart">
        <div><span>KODE:</span><strong>01</strong></div>
        <div><span>TOTAL</span><strong>Rp 16.000</strong></div>
        <p>ACCEPT: tambah/bayar · DECLINED: kurangi</p>
      </div>
    </div>
  )
}
