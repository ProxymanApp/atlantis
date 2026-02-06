import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  start(hostName: string | null): void;
  stop(): void;
  isRunning(): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('AtlantisReactNative');
