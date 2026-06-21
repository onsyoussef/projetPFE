import { useState } from 'react';
import { Form, Input, Button, Checkbox, Card } from 'antd';
import { MedicineBoxOutlined, EyeInvisibleOutlined, EyeTwoTone } from '@ant-design/icons';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

interface LoginFormValues {
  email: string;
  password: string;
  rememberMe: boolean;
}

export default function Login() {
  const { isAuthenticated, login, isLoggingIn } = useAuth();
  const [form] = Form.useForm<LoginFormValues>();

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  const onFinish = (values: LoginFormValues) => {
    login({
      email: values.email,
      password: values.password,
      rememberMe: values.rememberMe ?? false,
    });
  };

  return (
    <div className="login-bg flex min-h-screen items-center justify-center p-4">
      <Card
        className="w-full max-w-md shadow-card"
        style={{ borderRadius: 12, boxShadow: '0 2px 12px rgba(0,0,0,0.08)' }}
        bordered={false}
      >
        <div className="mb-8 text-center">
          <div
            className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl"
            style={{ background: 'linear-gradient(135deg, #1A6B8A, #2ECC9A)' }}
          >
            <MedicineBoxOutlined style={{ fontSize: 32, color: '#fff' }} />
          </div>
          <h1 className="text-2xl font-bold text-text-primary">HeadsApp Admin</h1>
          <p className="mt-1 text-sm text-text-secondary">
            Connectez-vous pour gérer les inscriptions médecins
          </p>
        </div>

        <Form
          form={form}
          layout="vertical"
          onFinish={onFinish}
          requiredMark={false}
          initialValues={{ rememberMe: false }}
        >
          <Form.Item
            label="Adresse e-mail"
            name="email"
            rules={[
              { required: true, message: 'Veuillez saisir votre e-mail' },
              { type: 'email', message: 'E-mail invalide' },
            ]}
          >
            <Input
              size="large"
              placeholder="admin@headsapp.tn"
              autoComplete="email"
              style={{ borderRadius: 8 }}
            />
          </Form.Item>

          <Form.Item
            label="Mot de passe"
            name="password"
            rules={[
              { required: true, message: 'Veuillez saisir votre mot de passe' },
              { min: 4, message: 'Minimum 4 caractères' },
            ]}
          >
            <Input.Password
              size="large"
              placeholder="••••••••"
              autoComplete="current-password"
              iconRender={(visible) =>
                visible ? <EyeTwoTone /> : <EyeInvisibleOutlined />
              }
              style={{ borderRadius: 8 }}
            />
          </Form.Item>

          <Form.Item name="rememberMe" valuePropName="checked">
            <Checkbox>Se souvenir de moi</Checkbox>
          </Form.Item>

          <Form.Item className="mb-0">
            <Button
              type="primary"
              htmlType="submit"
              size="large"
              block
              loading={isLoggingIn}
              style={{
                background: '#1A6B8A',
                borderColor: '#1A6B8A',
                borderRadius: 8,
                height: 44,
              }}
            >
              Se connecter
            </Button>
          </Form.Item>
        </Form>

        {import.meta.env.VITE_USE_MOCK === 'true' && (
          <p className="mt-4 text-center text-xs text-text-secondary">
            Mode démo : utilisez n&apos;importe quel e-mail et un mot de passe (4+ caractères)
          </p>
        )}
      </Card>
    </div>
  );
}
