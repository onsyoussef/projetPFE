import { useEffect, useState } from 'react';
import { Form, Input, Button, Switch, Card, Divider } from 'antd';
import { notification } from 'antd';
import { useAuthStore } from '@/store/authStore';

const NOTIF_KEY = 'headsapp-admin-notifications';

interface SettingsForm {
  name: string;
  email: string;
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
  emailAlerts: boolean;
}

function loadNotificationPref(): boolean {
  try {
    const raw = localStorage.getItem(NOTIF_KEY);
    if (raw) return JSON.parse(raw).emailAlerts ?? true;
  } catch {
    /* ignore */
  }
  return true;
}

export default function Settings() {
  const admin = useAuthStore((s) => s.admin);
  const [form] = Form.useForm<SettingsForm>();
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    form.setFieldsValue({
      name: admin?.name ?? '',
      email: admin?.email ?? '',
      emailAlerts: loadNotificationPref(),
    });
  }, [admin, form]);

  const onFinish = async (values: SettingsForm) => {
    if (values.newPassword && values.newPassword !== values.confirmPassword) {
      notification.error({
        message: 'Erreur',
        description: 'Les mots de passe ne correspondent pas.',
        placement: 'topRight',
      });
      return;
    }

    setSaving(true);
    await new Promise((r) => setTimeout(r, 600));

    localStorage.setItem(
      NOTIF_KEY,
      JSON.stringify({ emailAlerts: values.emailAlerts }),
    );

    setSaving(false);
    notification.success({
      message: 'Paramètres enregistrés',
      description: 'Vos préférences ont été mises à jour.',
      placement: 'topRight',
    });

    form.setFieldsValue({
      currentPassword: '',
      newPassword: '',
      confirmPassword: '',
    });
  };

  return (
    <div className="page-transition mx-auto max-w-2xl space-y-6">
      <Card
        title="Profil administrateur"
        className="shadow-card"
        style={{ borderRadius: 12, boxShadow: '0 2px 12px rgba(0,0,0,0.08)' }}
      >
        <Form form={form} layout="vertical" onFinish={onFinish}>
          <Form.Item
            label="Nom complet"
            name="name"
            rules={[{ required: true, message: 'Nom requis' }]}
          >
            <Input style={{ borderRadius: 8 }} />
          </Form.Item>

          <Form.Item
            label="E-mail"
            name="email"
            rules={[
              { required: true, message: 'E-mail requis' },
              { type: 'email', message: 'E-mail invalide' },
            ]}
          >
            <Input disabled style={{ borderRadius: 8 }} />
          </Form.Item>

          <Divider orientation="left">Changer le mot de passe</Divider>

          <Form.Item label="Mot de passe actuel" name="currentPassword">
            <Input.Password style={{ borderRadius: 8 }} />
          </Form.Item>

          <Form.Item label="Nouveau mot de passe" name="newPassword">
            <Input.Password style={{ borderRadius: 8 }} />
          </Form.Item>

          <Form.Item label="Confirmer le mot de passe" name="confirmPassword">
            <Input.Password style={{ borderRadius: 8 }} />
          </Form.Item>

          <Divider orientation="left">Notifications</Divider>

          <Form.Item
            label="Alertes e-mail pour les nouvelles inscriptions médecins"
            name="emailAlerts"
            valuePropName="checked"
          >
            <Switch />
          </Form.Item>

          <Form.Item>
            <Button
              type="primary"
              htmlType="submit"
              loading={saving}
              style={{
                background: '#1A6B8A',
                borderColor: '#1A6B8A',
                borderRadius: 8,
              }}
            >
              Enregistrer
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}
