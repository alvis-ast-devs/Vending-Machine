import { useEffect, useState } from 'react'

import { getPurchaseLogs } from './api.js'

const rupiah = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0,
})

const purchaseTime = new Intl.DateTimeFormat('id-ID', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'Asia/Jakarta',
})

export default function PurchaseLog() {
  const [purchases, setPurchases] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  async function loadPurchases() {
    setLoading(true)
    setError('')
    try {
      setPurchases(await getPurchaseLogs())
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let ignored = false

    getPurchaseLogs()
      .then((data) => {
        if (!ignored) {
          setPurchases(data)
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

  return (
    <section className="panel">
      <div className="panel-heading table-heading">
        <div>
          <p className="section-kicker">TRANSAKSI</p>
          <h2>Log Pembelian</h2>
          <p className="panel-description">
            Menampilkan maksimal 30 transaksi terbaru. Transaksi yang lebih lama
            dihapus otomatis dari database.
          </p>
        </div>
        <div className="table-tools">
          <span className="purchase-count">{purchases.length} / 30 transaksi</span>
          <button
            className="button button--secondary"
            disabled={loading}
            onClick={loadPurchases}
            type="button"
          >
            {loading ? 'Memuat…' : 'Muat Ulang'}
          </button>
        </div>
      </div>

      {error && <div className="alert alert--error">{error}</div>}

      <div className="table-scroll">
        <table className="purchase-log-table">
          <thead>
            <tr>
              <th>ID Transaksi</th>
              <th>Waktu</th>
              <th>Produk</th>
              <th>Jumlah</th>
              <th>Total</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {purchases.map((purchase) => (
              <tr key={purchase.id}>
                <td data-label="ID Transaksi">
                  <strong className="transaction-id">
                    {purchase.transaction_id || `LOG-${String(purchase.id).padStart(4, '0')}`}
                  </strong>
                </td>
                <td data-label="Waktu">
                  <time dateTime={purchase.created_at}>
                    {purchaseTime.format(new Date(purchase.created_at))} WIB
                  </time>
                </td>
                <td data-label="Produk">
                  <ul className="purchase-items">
                    {purchase.items.map((item) => (
                      <li key={item.id}>
                        <span>{item.product_name}</span>
                        <small>
                          Slot {item.slot_code} · {rupiah.format(item.unit_price)} ×{' '}
                          {item.quantity}
                        </small>
                      </li>
                    ))}
                  </ul>
                </td>
                <td data-label="Jumlah">{purchase.total_items} item</td>
                <td data-label="Total">
                  <strong className="purchase-total">
                    {rupiah.format(purchase.total_amount)}
                  </strong>
                </td>
                <td data-label="Status">
                  <span className="status-chip status-chip--active">Berhasil</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {!loading && purchases.length === 0 && !error && (
          <div className="empty-state">Belum ada pembelian yang tercatat.</div>
        )}
      </div>
    </section>
  )
}
