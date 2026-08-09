import { useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Camera, CloudArrowUp, CheckCircle } from 'phosphor-react';
import { toast } from 'sonner';
import { api, Invoice } from '../../lib/api';
import { Button, DataTable, Panel, Status } from '../../components/ui';
import { useSession } from '../../store/session';

export function ClientApp() {
  const companyCode = useSession((s) => s.companyCode);
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [lastUpload, setLastUpload] = useState<string>();

  const history = useQuery({
    queryKey: ['invoices', companyCode],
    queryFn: () => api.invoices(companyCode),
    enabled: !!companyCode,
    refetchInterval: 8000,
  });

  async function onPick(file?: File | null) {
    if (!file || !companyCode) return;
    setUploading(true);
    try {
      const invoice = await api.captureInvoice(companyCode, file);
      setLastUpload(invoice._id);
      toast.success('Bill saved. AI extraction runs on the server — Admin will verify.');
      queryClient.invalidateQueries({ queryKey: ['invoices', companyCode] });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  const pending = history.data?.filter((i) => i.status === 'processing' || i.status === 'pending_review').length ?? 0;

  return (
    <div className="page-grid client-lite">
      <Panel className="span-12">
        <div className="panel-head">
          <div><Camera size={22} /><h2>Capture bill</h2></div>
          <Status tone={uploading ? 'warn' : 'good'}>{uploading ? 'Uploading…' : 'Ready'}</Status>
        </div>
        <p className="muted">
          Photograph or pick a bill. The image is stored immediately on the server. Gemini extracts fields in the background —
          you do not wait. Admin opens the bill image (zoom) to verify accuracy.
        </p>
        <label className={`dropzone dropzone-fast${uploading ? ' is-busy' : ''}`}>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            disabled={uploading || !companyCode}
            onChange={(e) => void onPick(e.target.files?.[0])}
          />
          <div className="dropzone-empty">
            {uploading ? <CloudArrowUp size={40} weight="thin" className="spin-soft" /> : <Camera size={40} weight="thin" />}
            <strong>{uploading ? 'Uploading to server…' : 'Tap to capture or choose image'}</strong>
            <p>No on-device AI. Upload only — processing is server-side.</p>
          </div>
        </label>
        <div className="row-actions">
          <Button type="button" disabled={uploading || !companyCode} onClick={() => fileRef.current?.click()}>
            {uploading ? 'Uploading…' : 'New bill image'}
          </Button>
          {lastUpload && (
            <span className="muted tiny inline-ok"><CheckCircle size={14} /> Sent · Admin queue</span>
          )}
          <Status tone="info">{pending} awaiting admin</Status>
        </div>
      </Panel>

      <Panel className="span-12">
        <h2>Recent uploads</h2>
        <DataTable>
          <thead>
            <tr><th>Status</th><th>Vendor</th><th>Invoice</th><th>Invoice amount</th><th>When</th></tr>
          </thead>
          <tbody>
            {history.data?.slice(0, 20).map((item: Invoice) => (
              <tr key={item._id}>
                <td>
                  <Status tone={item.status === 'processing' ? 'warn' : item.status === 'pending_review' ? 'info' : 'good'}>
                    {item.status === 'processing' ? 'AI processing' : item.status === 'pending_review' ? 'Ready for admin' : item.status.replaceAll('_', ' ')}
                  </Status>
                </td>
                <td>{item.status === 'processing' ? '—' : item.vendorName}</td>
                <td>{item.status === 'processing' ? '—' : item.invoiceNumber}</td>
                <td>{item.status === 'processing' ? '—' : `₹${Number(item.invoiceAmount || 0).toLocaleString()}`}</td>
                <td><small className="muted">{item._id === lastUpload ? 'Just now' : ''}</small></td>
              </tr>
            ))}
            {!history.data?.length && (
              <tr><td colSpan={5}><p className="muted">No bills yet. Capture one above.</p></td></tr>
            )}
          </tbody>
        </DataTable>
      </Panel>
    </div>
  );
}
