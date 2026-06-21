import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button, Result } from 'antd';

interface Props {
  children: ReactNode;
  onRetry?: () => {
    resetErrorBoundary?: () => void;
  };
}

interface State {
  hasError: boolean;
}

export default class QueryErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    if (!import.meta.env.PROD) {
      console.error('QueryErrorBoundary:', error, info);
    }
  }

  handleRetry = () => {
    this.setState({ hasError: false });
    this.props.onRetry?.();
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-[400px] items-center justify-center p-8">
          <Result
            status="error"
            title="Une erreur est survenue"
            subTitle="Impossible de charger les données. Veuillez réessayer."
            extra={
              <Button type="primary" onClick={this.handleRetry}>
                Réessayer
              </Button>
            }
          />
        </div>
      );
    }

    return this.props.children;
  }
}
