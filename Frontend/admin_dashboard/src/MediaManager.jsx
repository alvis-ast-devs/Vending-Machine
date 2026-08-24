import { useEffect, useState } from 'react'

import {
  deleteMedia,
  getMediaCatalog,
  mediaFileUrl,
  uploadAd,
  uploadHomescreen,
  uploadTutorial,
} from './api.js'

const adAccept = 'image/jpeg,image/png,image/webp,image/gif,image/bmp,image/x-ms-bmp,video/mp4,video/webm,video/quicktime,video/x-matroska'
const videoAccept = 'video/mp4,video/webm,video/quicktime,video/x-matroska'

export default function MediaManager() {
  const [catalog, setCatalog] = useState({
    ads: [],
    tutorial: null,
    homescreen: null,
  })
  const [adFiles, setAdFiles] = useState([])
  const [tutorialFile, setTutorialFile] = useState(null)
  const [homescreenFile, setHomescreenFile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busyKey, setBusyKey] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [inputVersions, setInputVersions] = useState({
    ads: 0,
    tutorial: 0,
    homescreen: 0,
  })

  function resetFileInput(key) {
    setInputVersions((versions) => ({
      ...versions,
      [key]: versions[key] + 1,
    }))
  }

  async function loadCatalog() {
    setLoading(true)
    try {
      setCatalog(await getMediaCatalog())
      setError('')
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    let ignored = false

    getMediaCatalog()
      .then((data) => {
        if (!ignored) {
          setCatalog(data)
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

  async function handleAdUpload(event) {
    event.preventDefault()
    if (adFiles.length === 0) return

    setBusyKey('ads')
    setError('')
    setNotice('')
    let completed = 0
    try {
      for (const file of adFiles) {
        await uploadAd(file)
        completed += 1
      }
      setNotice(`${completed} media iklan berhasil diunggah.`)
      setAdFiles([])
      resetFileInput('ads')
    } catch (requestError) {
      setError(
        completed > 0
          ? `${completed} file berhasil, lalu unggahan berhenti: ${requestError.message}`
          : requestError.message,
      )
    } finally {
      await loadCatalog()
      setBusyKey('')
    }
  }

  async function handleTutorialUpload(event) {
    event.preventDefault()
    if (!tutorialFile) return

    setBusyKey('tutorial')
    setError('')
    setNotice('')
    try {
      await uploadTutorial(tutorialFile)
      setNotice('Video tutorial berhasil disimpan.')
      setTutorialFile(null)
      resetFileInput('tutorial')
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      await loadCatalog()
      setBusyKey('')
    }
  }

  async function handleHomescreenUpload(event) {
    event.preventDefault()
    if (!homescreenFile) return

    setBusyKey('homescreen')
    setError('')
    setNotice('')
    try {
      await uploadHomescreen(homescreenFile)
      setNotice('Media homescreen berhasil disimpan.')
      setHomescreenFile(null)
      resetFileInput('homescreen')
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      await loadCatalog()
      setBusyKey('')
    }
  }

  async function handleDelete(media) {
    const confirmed = window.confirm(`Hapus ${media.original_name}?`)
    if (!confirmed) return

    setBusyKey(`delete-${media.id}`)
    setError('')
    setNotice('')
    try {
      await deleteMedia(media.id)
      setNotice(`${media.original_name} berhasil dihapus.`)
      await loadCatalog()
    } catch (requestError) {
      setError(requestError.message)
    } finally {
      setBusyKey('')
    }
  }

  return (
    <section className="panel media-panel">
      <div className="panel-heading media-heading">
        <div>
          <p className="section-kicker">KONTEN LAYAR</p>
          <h2>Iklan, tutorial, dan homescreen</h2>
          <p className="panel-description">
            Gunakan rasio 9:16; rasio lain akan dipotong
            otomatis agar memenuhi layar.
          </p>
        </div>
        <button
          className="button button--secondary"
          disabled={loading}
          onClick={loadCatalog}
          type="button"
        >
          {loading ? 'Memuat...' : 'Muat Ulang Media'}
        </button>
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

      <div className="media-sections">
        <section className="media-section" aria-labelledby="tutorial-heading">
          <div className="media-section-heading">
            <div>
              <h3 id="tutorial-heading">Video tutorial</h3>
              <p>
                Hanya satu video 9:16. Upload baru otomatis menggantikan yang
                lama.
              </p>
            </div>
          </div>

          <form className="upload-form" onSubmit={handleTutorialUpload}>
            <div className="file-field">
              <label htmlFor="tutorial-media-input">Pilih video tutorial</label>
              <div className="upload-control-row">
                <input
                  accept={videoAccept}
                  id="tutorial-media-input"
                  key={`tutorial-${inputVersions.tutorial}`}
                  onChange={(event) =>
                    setTutorialFile(event.target.files?.[0] ?? null)
                  }
                  type="file"
                />
                <button
                  className="button button--primary upload-submit"
                  disabled={busyKey !== '' || !tutorialFile}
                  type="submit"
                >
                  {busyKey === 'tutorial' ? 'Mengunggah...' : 'Upload Tutorial'}
                </button>
              </div>
              <span>Rasio 9:16 • MP4, WebM, MOV, atau MKV</span>
            </div>
          </form>

          {catalog.tutorial ? (
            <div className="single-media-preview">
              <MediaCard
                busy={busyKey === `delete-${catalog.tutorial.id}`}
                media={catalog.tutorial}
                onDelete={handleDelete}
              />
            </div>
          ) : (
            <MediaEmptyState>
              Belum ada tutorial. Deteksi pengguna akan langsung membuka Home.
            </MediaEmptyState>
          )}
        </section>

        <section className="media-section" aria-labelledby="homescreen-heading">
          <div className="media-section-heading">
            <div>
              <h3 id="homescreen-heading">Homescreen</h3>
              <p>
                Satu foto atau video 9:16. Jika kosong, layar Home bawaan tetap
                digunakan.
              </p>
            </div>
          </div>

          <form className="upload-form" onSubmit={handleHomescreenUpload}>
            <div className="file-field">
              <label htmlFor="homescreen-media-input">
                Pilih foto atau video homescreen
              </label>
              <div className="upload-control-row">
                <input
                  accept={adAccept}
                  id="homescreen-media-input"
                  key={`homescreen-${inputVersions.homescreen}`}
                  onChange={(event) =>
                    setHomescreenFile(event.target.files?.[0] ?? null)
                  }
                  type="file"
                />
                <button
                  className="button button--primary upload-submit"
                  disabled={busyKey !== '' || !homescreenFile}
                  type="submit"
                >
                  {busyKey === 'homescreen'
                    ? 'Mengunggah...'
                    : 'Upload Homescreen'}
                </button>
              </div>
              <span>
                Rasio 9:16 • PNG, JPG, WebP, GIF, BMP, MP4, WebM, MOV, atau MKV
              </span>
            </div>
          </form>

          {catalog.homescreen ? (
            <div className="single-media-preview">
              <MediaCard
                busy={busyKey === `delete-${catalog.homescreen.id}`}
                media={catalog.homescreen}
                onDelete={handleDelete}
              />
            </div>
          ) : (
            <MediaEmptyState>
              Belum ada media homescreen. Aplikasi memakai layar Home bawaan.
            </MediaEmptyState>
          )}
        </section>

        <section
          className="media-section media-section--wide"
          aria-labelledby="ads-heading"
        >
          <div className="media-section-heading">
            <div>
              <h3 id="ads-heading">Iklan</h3>
              <p>
                Unggah beberapa foto atau video 9:16. Semuanya diputar
                bergantian.
              </p>
            </div>
            <span className="media-count">{catalog.ads.length} media</span>
          </div>

          <form className="upload-form" onSubmit={handleAdUpload}>
            <div className="file-field">
              <label htmlFor="ad-media-input">Pilih foto atau video iklan</label>
              <div className="upload-control-row">
                <input
                  accept={adAccept}
                  id="ad-media-input"
                  key={`ads-${inputVersions.ads}`}
                  multiple
                  onChange={(event) =>
                    setAdFiles([...(event.target.files ?? [])])
                  }
                  type="file"
                />
                <button
                  className="button button--primary upload-submit"
                  disabled={busyKey !== '' || adFiles.length === 0}
                  type="submit"
                >
                  {busyKey === 'ads'
                    ? `Mengunggah ${adFiles.length} file...`
                    : 'Upload Iklan'}
                </button>
              </div>
              <span>
                Rasio 9:16 • PNG, JPG, WebP, GIF, BMP, MP4, WebM, MOV, atau MKV
              </span>
            </div>
          </form>

          {catalog.ads.length > 0 ? (
            <div className="media-grid">
              {catalog.ads.map((media) => (
                <MediaCard
                  busy={busyKey === `delete-${media.id}`}
                  key={media.id}
                  media={media}
                  onDelete={handleDelete}
                />
              ))}
            </div>
          ) : (
            <MediaEmptyState>
              Belum ada iklan. Aplikasi akan tetap menampilkan Home.
            </MediaEmptyState>
          )}
        </section>
      </div>
    </section>
  )
}

function MediaCard({ media, busy, onDelete }) {
  const source = mediaFileUrl(media.url)

  return (
    <article className="media-card">
      <div className="media-preview">
        {media.media_type === 'image' ? (
          <img alt={media.original_name} loading="lazy" src={source} />
        ) : (
          <video controls muted preload="metadata" src={source} />
        )}
        <span className="media-type">
          {media.media_type === 'image' ? 'FOTO' : 'VIDEO'}
        </span>
        <span className="media-ratio">PREVIEW 9:16</span>
      </div>
      <div className="media-card-footer">
        <span title={media.original_name}>{media.original_name}</span>
        <button
          className="button button--small button--danger"
          disabled={busy}
          onClick={() => onDelete(media)}
          type="button"
        >
          {busy ? 'Menghapus...' : 'Hapus'}
        </button>
      </div>
    </article>
  )
}

function MediaEmptyState({ children }) {
  return <div className="media-empty-state">{children}</div>
}
