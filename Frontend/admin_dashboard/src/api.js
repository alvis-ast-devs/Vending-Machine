export const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || ''
).replace(/\/$/, '')

async function request(path, options = {}) {
  const isFormData = options.body instanceof FormData
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      Accept: 'application/json',
      ...(options.body && !isFormData
        ? { 'Content-Type': 'application/json' }
        : {}),
      ...options.headers,
    },
  })

  const payload = await response.json().catch(() => null)
  if (!response.ok) {
    const rawDetail = payload?.detail
    const detail = Array.isArray(rawDetail)
      ? rawDetail.map((item) => item.msg).join(', ')
      : rawDetail
    throw new Error(detail || `Permintaan gagal (${response.status})`)
  }

  return payload
}

export function getProducts() {
  return request('/api/products?include_inactive=true')
}

export function getMediaCatalog() {
  return request('/api/media')
}

export function getPurchaseLogs() {
  return request('/api/purchases')
}

export function getThemeSettings() {
  return request('/api/theme')
}

export function updateThemeSettings(theme) {
  return request('/api/theme', {
    method: 'PUT',
    body: JSON.stringify(theme),
  })
}

export function uploadAd(file) {
  const body = new FormData()
  body.append('file', file)
  return request('/api/media/ads', { method: 'POST', body })
}

export function uploadTutorial(file) {
  const body = new FormData()
  body.append('file', file)
  return request('/api/media/tutorial', { method: 'POST', body })
}

export function uploadHomescreen(file) {
  const body = new FormData()
  body.append('file', file)
  return request('/api/media/homescreen', { method: 'POST', body })
}

export function deleteMedia(mediaId) {
  return request(`/api/media/${mediaId}`, { method: 'DELETE' })
}

export function mediaFileUrl(path) {
  if (!path) return ''
  return /^https?:\/\//i.test(path) ? path : `${API_BASE_URL}${path}`
}

export function updateProduct(productId, changes) {
  return request(`/api/products/${productId}`, {
    method: 'PUT',
    body: JSON.stringify(changes),
  })
}

export function uploadProductImage(productId, file) {
  const body = new FormData()
  body.append('file', file)
  return request(`/api/products/${productId}/image`, { method: 'POST', body })
}

export function deleteProductImage(productId) {
  return request(`/api/products/${productId}/image`, { method: 'DELETE' })
}

export function deactivateProduct(productId) {
  return request(`/api/products/${productId}/deactivate`, {
    method: 'PUT',
  })
}

export function restockProduct(productId) {
  return request(`/api/products/${productId}/restock`, {
    method: 'PUT',
  })
}
