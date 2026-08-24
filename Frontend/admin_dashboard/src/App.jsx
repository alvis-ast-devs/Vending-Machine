import { useEffect, useMemo, useState } from 'react'

import {
  API_BASE_URL,
  deactivateProduct,
  deleteProductImage,
  getProducts,
  mediaFileUrl,
  restockProduct,
  updateProduct,
  uploadProductImage,
} from './api.js'
import MediaManager from './MediaManager.jsx'
import PurchaseLog from './PurchaseLog.jsx'
import ThemeSettings from './ThemeSettings.jsx'

const rupiah = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0,
})

const tabs = [
  { id: 'overview', label: 'Ringkasan' },
  { id: 'products', label: 'Produk' },
  { id: 'purchases', label: 'Log Pembelian' },
  { id: 'media', label: 'Konten Layar' },
]

const productImageAccept =
  'image/png,image/jpeg,image/webp,image/gif,image/bmp,image/x-ms-bmp'

export default function App() {
  const [activeTab, setActiveTab] = useState('overview')
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busyKey, setBusyKey] = useState('')
  const [editingId, setEditingId] = useState(null)
  const [editForm, setEditForm] = useState({ name: '', price: '', stock: '' })
  const [searchQuery, setSearchQuery] = useState('')

  useEffect(() => {
    let ignored = false

    getProducts()
      .then((data) => {
        if (!ignored) {
          setProducts(data)
          setError('')
        }
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

  const summary = useMemo(() => {
    const active = products.filter((product) => product.is_active)
    return {
      active: active.length,
      totalStock: active.reduce((total, product) => total + product.stock, 0),
      empty: active.filter((product) => product.stock === 0).length,
    }
  }, [products])

  const filteredProducts = useMemo(() => {
    const normalizedQuery = searchQuery.trim().toLocaleLowerCase('id-ID')
    const orderedProducts = [...products].sort((a, b) =>
      a.slot_code.localeCompare(b.slot_code),
    )
    if (!normalizedQuery) return orderedProducts

    return orderedProducts.filter(
      (product) =>
        product.name.toLocaleLowerCase('id-ID').includes(normalizedQuery) ||
        product.slot_code.includes(normalizedQuery),
    )
  }, [products, searchQuery])

  async function refreshProducts() {
    setLoading(true)
    setError('')
    try {
      setProducts(await getProducts())
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      setLoading(false)
    }
  }

  async function runMutation(key, action, successMessage) {
    setBusyKey(key)
    setError('')
    setNotice('')
    try {
      await action()
      setProducts(await getProducts())
      setNotice(successMessage)
      return true
    } catch (requestError) {
      setError(requestError.message)
      return false
    } finally {
      setBusyKey('')
    }
  }

  function startEditing(product) {
    setEditingId(product.id)
    setEditForm({
      name: product.name,
      price: String(product.price),
      stock: String(product.stock),
    })
    setError('')
    setNotice('')
  }

  async function saveEdit(product) {
    const succeeded = await runMutation(
      `edit-${product.id}`,
      () =>
        updateProduct(product.id, {
          name: editForm.name.trim(),
          price: Number(editForm.price),
          stock: Number(editForm.stock),
        }),
      `Produk ${product.slot_code} berhasil diperbarui.`,
    )
    if (succeeded) setEditingId(null)
  }

  async function handleProductImage(product, file) {
    await runMutation(
      `image-${product.id}`,
      () => uploadProductImage(product.id, file),
      `Foto ${product.name} berhasil diperbarui.`,
    )
  }

  async function handleDeleteProductImage(product) {
    const confirmed = window.confirm(
      `Hapus foto ${product.name} dan gunakan gambar default?`,
    )
    if (!confirmed) return

    await runMutation(
      `image-${product.id}`,
      () => deleteProductImage(product.id),
      `Foto ${product.name} dihapus. Gambar default akan digunakan.`,
    )
  }

  async function handleDeactivate(product) {
    const confirmed = window.confirm(
      `Nonaktifkan ${product.name} (${product.slot_code})?`,
    )
    if (!confirmed) return

    await runMutation(
      `deactivate-${product.id}`,
      () => deactivateProduct(product.id),
      `Produk ${product.slot_code} dinonaktifkan.`,
    )
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">ACCESS POINT VENDING MACHINE</p>
          <h1>Dashboard Admin</h1>
          <p className="subtitle">
            Kelola produk, stok, riwayat pembelian, dan konten layar mesin.
          </p>
        </div>
        <div className="topbar-actions">
          <button
            aria-label="Buka pengaturan palet warna"
            className={`theme-settings-button ${activeTab === 'theme' ? 'theme-settings-button--active' : ''}`}
            onClick={() => setActiveTab('theme')}
            title="Pengaturan tampilan vending machine"
            type="button"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Zm8.4 4.7-1.8 1.05c.04.25.06.5.06.75s-.02.5-.06.75l1.8 1.05-2 3.46-1.82-1.06c-.39.32-.82.57-1.29.75V22h-4v-2.05a7.1 7.1 0 0 1-1.29-.75L8.2 20.26l-2-3.46L8 15.75A4.8 4.8 0 0 1 7.94 15c0-.25.02-.5.06-.75L6.2 13.2l2-3.46L10.02 10c.39-.32.82-.57 1.29-.75V7h4v2.05c.47.18.9.43 1.29.75l1.82-1.06 2 3.46Z" />
            </svg>
            <span>
              <small>Desain mesin</small>
              <strong>Pengaturan warna</strong>
            </span>
          </button>
          <div className="server-status" title={API_BASE_URL}>
            <span className="status-dot" aria-hidden="true" />
            <span>Backend</span>
            <strong>{API_BASE_URL || 'Database backend lokal'}</strong>
          </div>
        </div>
      </header>

      <nav className="dashboard-nav" aria-label="Navigasi dashboard">
        <div className="nav-tabs" role="tablist">
          {tabs.map((tab) => (
            <button
              aria-controls={`${tab.id}-panel`}
              aria-selected={activeTab === tab.id}
              className={`nav-tab ${activeTab === tab.id ? 'nav-tab--active' : ''}`}
              id={`${tab.id}-tab`}
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              role="tab"
              type="button"
            >
              {tab.label}
            </button>
          ))}
        </div>
      </nav>

      <main>
        {activeTab === 'overview' && (
          <section
            aria-labelledby="overview-tab"
            id="overview-panel"
            role="tabpanel"
          >
            <section className="summary-grid" aria-label="Ringkasan produk">
              <SummaryCard
                accent="green"
                label="Produk aktif"
                value={summary.active}
              />
              <SummaryCard
                accent="blue"
                label="Total stok"
                value={summary.totalStock}
              />
              <SummaryCard
                accent="red"
                label="Slot kosong"
                value={summary.empty}
              />
            </section>

            <section className="panel overview-panel">
              <div>
                <p className="section-kicker">AKSES CEPAT</p>
                <h2>Pilih bagian yang ingin dikelola</h2>
                <p className="panel-description">
                  Ringkasan utama selalu tersedia di halaman depan agar kondisi
                  mesin dapat diperiksa sebelum melakukan perubahan.
                </p>
              </div>
              <div className="overview-actions">
                <button
                  className="overview-action"
                  onClick={() => setActiveTab('products')}
                  type="button"
                >
                  <span>Produk</span>
                  <strong>Edit katalog, stok, dan foto</strong>
                </button>
                <button
                  className="overview-action"
                  onClick={() => setActiveTab('purchases')}
                  type="button"
                >
                  <span>Log Pembelian</span>
                  <strong>Lihat 30 transaksi terbaru</strong>
                </button>
                <button
                  className="overview-action"
                  onClick={() => setActiveTab('media')}
                  type="button"
                >
                  <span>Konten Layar</span>
                  <strong>Kelola iklan, tutorial, dan homescreen</strong>
                </button>
              </div>
            </section>
          </section>
        )}

        {activeTab === 'products' && (
          <section
            aria-labelledby="products-tab"
            id="products-panel"
            role="tabpanel"
          >
            <section className="panel">
              <div className="panel-heading table-heading">
                <div>
                  <p className="section-kicker">KATALOG</p>
                  <h2>Daftar produk</h2>
                  <p className="panel-description">
                    PNG disarankan untuk hasil terbaik. JPG, WebP, GIF, dan BMP
                    juga didukung.
                  </p>
                </div>
                <div className="table-tools">
                  <label className="search-field">
                    <span className="visually-hidden">
                      Cari produk atau nomor slot
                    </span>
                    <input
                      aria-label="Cari produk atau nomor slot"
                      placeholder="Cari nama atau nomor slot..."
                      type="search"
                      value={searchQuery}
                      onChange={(event) => setSearchQuery(event.target.value)}
                    />
                  </label>
                  {searchQuery && (
                    <button
                      className="button button--ghost"
                      onClick={() => setSearchQuery('')}
                      type="button"
                    >
                      Hapus
                    </button>
                  )}
                  <button
                    className="button button--secondary"
                    disabled={loading}
                    onClick={refreshProducts}
                    type="button"
                  >
                    {loading ? 'Memuat...' : 'Muat Ulang'}
                  </button>
                </div>
              </div>

              {error && (
                <div className="alert alert--error" role="alert">
                  {error}
                </div>
              )}
              {notice && (
                <div className="alert alert--success" role="status">
                  {notice}
                </div>
              )}

              <div className="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Slot</th>
                      <th>Foto</th>
                      <th>Nama</th>
                      <th>Harga</th>
                      <th>Stok</th>
                      <th>Status</th>
                      <th className="actions-heading">Aksi</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredProducts.map((product) => {
                      const isEditing = editingId === product.id
                      const rowBusy = busyKey.endsWith(`-${product.id}`)

                      return (
                        <tr
                          className={product.is_active ? '' : 'inactive-row'}
                          key={product.id}
                        >
                          <td data-label="Slot">
                            <span
                              aria-label={`Nomor slot ${product.slot_code}`}
                              className="slot-code"
                            >
                              {product.slot_code}
                            </span>
                          </td>
                          <td data-label="Foto">
                            <div className="product-image-cell">
                              <ProductImage
                                key={product.image_url ?? 'default'}
                                product={product}
                              />
                              <div className="product-image-actions">
                                <label
                                  className={`button button--small button--secondary image-upload-button ${rowBusy ? 'image-upload-button--disabled' : ''}`}
                                >
                                  {busyKey === `image-${product.id}`
                                    ? 'Mengunggah...'
                                    : product.image_url
                                      ? 'Ganti'
                                      : 'Upload'}
                                  <input
                                    accept={productImageAccept}
                                    disabled={rowBusy}
                                    onChange={(event) => {
                                      const file = event.target.files?.[0]
                                      event.target.value = ''
                                      if (file) handleProductImage(product, file)
                                    }}
                                    type="file"
                                  />
                                </label>
                                {product.image_url && (
                                  <button
                                    aria-label={`Hapus foto ${product.name}`}
                                    className="image-remove-button"
                                    disabled={rowBusy}
                                    onClick={() =>
                                      handleDeleteProductImage(product)
                                    }
                                    title="Gunakan gambar default"
                                    type="button"
                                  >
                                    Hapus
                                  </button>
                                )}
                              </div>
                            </div>
                          </td>
                          <td data-label="Nama">
                            {isEditing ? (
                              <input
                                aria-label={`Nama produk slot ${product.slot_code}`}
                                className="table-input table-input--name"
                                maxLength="120"
                                value={editForm.name}
                                onChange={(event) =>
                                  setEditForm((current) => ({
                                    ...current,
                                    name: event.target.value,
                                  }))
                                }
                              />
                            ) : (
                              <strong>{product.name}</strong>
                            )}
                          </td>
                          <td data-label="Harga">
                            {isEditing ? (
                              <input
                                aria-label={`Harga produk slot ${product.slot_code}`}
                                className="table-input table-input--price"
                                min="0"
                                step="1"
                                type="number"
                                value={editForm.price}
                                onChange={(event) =>
                                  setEditForm((current) => ({
                                    ...current,
                                    price: event.target.value,
                                  }))
                                }
                              />
                            ) : (
                              rupiah.format(product.price)
                            )}
                          </td>
                          <td data-label="Stok">
                            {isEditing ? (
                              <input
                                aria-label={`Stok produk ${product.slot_code}`}
                                className="table-input table-input--stock"
                                min="0"
                                step="1"
                                type="number"
                                value={editForm.stock}
                                onChange={(event) =>
                                  setEditForm((current) => ({
                                    ...current,
                                    stock: event.target.value,
                                  }))
                                }
                              />
                            ) : (
                              <span
                                className={`stock ${product.stock === 0 ? 'stock--empty' : ''}`}
                              >
                                {product.stock}
                              </span>
                            )}
                          </td>
                          <td data-label="Status">
                            <span
                              className={`status-chip ${
                                product.is_active
                                  ? 'status-chip--active'
                                  : 'status-chip--inactive'
                              }`}
                            >
                              {product.is_active ? 'Aktif' : 'Nonaktif'}
                            </span>
                          </td>
                          <td data-label="Aksi">
                            <div className="action-group">
                              {isEditing ? (
                                <>
                                  <button
                                    className="button button--small button--primary"
                                    disabled={
                                      rowBusy ||
                                      !editForm.name.trim() ||
                                      editForm.price === '' ||
                                      Number(editForm.price) < 0 ||
                                      !Number.isInteger(Number(editForm.price)) ||
                                      editForm.stock === '' ||
                                      Number(editForm.stock) < 0 ||
                                      !Number.isInteger(Number(editForm.stock))
                                    }
                                    onClick={() => saveEdit(product)}
                                    type="button"
                                  >
                                    Simpan
                                  </button>
                                  <button
                                    className="button button--small button--ghost"
                                    disabled={rowBusy}
                                    onClick={() => setEditingId(null)}
                                    type="button"
                                  >
                                    Batal
                                  </button>
                                </>
                              ) : (
                                <>
                                  <button
                                    className="button button--small button--secondary"
                                    disabled={rowBusy}
                                    onClick={() => startEditing(product)}
                                    type="button"
                                  >
                                    Edit
                                  </button>
                                  <button
                                    className="button button--small button--restock"
                                    disabled={rowBusy || !product.is_active}
                                    onClick={() =>
                                      runMutation(
                                        `restock-${product.id}`,
                                        () => restockProduct(product.id),
                                        `Stok produk ${product.slot_code} kembali penuh.`,
                                      )
                                    }
                                    type="button"
                                  >
                                    Restock Penuh
                                  </button>
                                  {product.is_active ? (
                                    <button
                                      className="button button--small button--danger"
                                      disabled={rowBusy}
                                      onClick={() => handleDeactivate(product)}
                                      type="button"
                                    >
                                      Nonaktifkan
                                    </button>
                                  ) : (
                                    <button
                                      className="button button--small button--activate"
                                      disabled={rowBusy}
                                      onClick={() =>
                                        runMutation(
                                          `activate-${product.id}`,
                                          () =>
                                            updateProduct(product.id, {
                                              is_active: true,
                                            }),
                                          `Produk ${product.slot_code} diaktifkan.`,
                                        )
                                      }
                                      type="button"
                                    >
                                      Aktifkan
                                    </button>
                                  )}
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>

                {!loading && filteredProducts.length === 0 && (
                  <div className="empty-state">
                    {searchQuery.trim()
                      ? `Produk "${searchQuery.trim()}" tidak ditemukan.`
                      : 'Belum ada produk di database.'}
                  </div>
                )}
              </div>
            </section>
          </section>
        )}

        {activeTab === 'media' && (
          <section
            aria-labelledby="media-tab"
            id="media-panel"
            role="tabpanel"
          >
            <MediaManager />
          </section>
        )}

        {activeTab === 'purchases' && (
          <section
            aria-labelledby="purchases-tab"
            id="purchases-panel"
            role="tabpanel"
          >
            <PurchaseLog />
          </section>
        )}

        {activeTab === 'theme' && <ThemeSettings />}
      </main>

      <footer>
        @ Copyright Aruvisu
      </footer>
    </div>
  )
}

function SummaryCard({ label, value, accent }) {
  return (
    <article className={`summary-card summary-card--${accent}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}

function ProductImage({ product }) {
  const [failed, setFailed] = useState(false)

  if (!product.image_url || failed) {
    return (
      <div
        aria-label={`Gambar default ${product.name}`}
        className="product-image product-image--default"
      >
        <span aria-hidden="true">▧</span>
      </div>
    )
  }

  return (
    <img
      alt={product.name}
      className="product-image"
      loading="lazy"
      onError={() => setFailed(true)}
      src={mediaFileUrl(product.image_url)}
    />
  )
}
