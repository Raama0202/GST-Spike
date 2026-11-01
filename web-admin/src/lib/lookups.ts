import { api } from '../api/client'
import type { Company, Items, NamedResource, Page } from '../api/types'
import type { PickerOption } from '../components/Picker'
import { cached, invalidate } from './cache'

export const BRANCHES_PATH = '/admin/company/branches'
export const CATEGORIES_PATH = '/admin/company/categories'

export function loadResources(path: string): Promise<NamedResource[]> {
  return cached(path, () => api<Items<NamedResource>>(path).then((r) => r.items))
}

export const loadBranches = () => loadResources(BRANCHES_PATH)
export const loadCategories = () => loadResources(CATEGORIES_PATH)
export const invalidateResources = (path: string) => invalidate(path)

export function searchCompanies(q: string): Promise<PickerOption[]> {
  return api<Page<Company>>('/super/companies', { query: { q: q || undefined, pageSize: 20 } })
    .then((r) => r.items.map((c) => ({ id: c.id, label: c.name, sub: c.adminEmail ?? c.activationCode })))
}
