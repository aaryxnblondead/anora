import { useRouter } from 'expo-router';
import { Text, View, StyleSheet } from 'react-native';
import { Card } from '../../components/ui/Card';
import Button from '../../components/ui/Button';

export default function PrivacyScreen() {
  const router = useRouter();

  return (
    <View style={styles.container}>
      <View style={styles.progressContainer}>
         {/* Simple Progress Bar */}
        <View style={[styles.progressBar, { width: '33%' }]} />
      </View>

      <Text style={styles.header}>Zero Knowledge.</Text>
      
      <Card style={styles.card}>
        <View style={styles.bulletPoint}>
          <Text style={styles.icon}>🔒</Text>
          <Text style={styles.text}>Your words never leave this phone unencrypted.</Text>
        </View>
        <View style={styles.bulletPoint}>
          <Text style={styles.icon}>🤖</Text>
          <Text style={styles.text}>AI runs locally on your device to find patterns.</Text>
        </View>
        <View style={styles.bulletPoint}>
          <Text style={styles.icon}>👩‍⚕️</Text>
          <Text style={styles.text}>Only you can choose to share summaries with your doctor.</Text>
        </View>
      </Card>

      <View style={styles.footer}>
        <Button 
          title="I Understand" 
          onPress={() => router.push('/(auth)/setup')} 
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F7F8FB', padding: 24, paddingTop: 60 },
  progressContainer: { 
    height: 4, 
    backgroundColor: '#E2E8F0', 
    borderRadius: 2, 
    marginBottom: 32 
  },
  progressBar: { 
    height: '100%', 
    backgroundColor: '#5C6AC4', 
    borderRadius: 2 
  },
  header: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#1E293B',
    marginBottom: 24,
  },
  card: { gap: 24 },
  bulletPoint: { flexDirection: 'row', gap: 16, alignItems: 'center' },
  icon: { fontSize: 24 },
  text: { fontSize: 16, color: '#334155', lineHeight: 24, flex: 1 },
  footer: { marginTop: 'auto' },
});
