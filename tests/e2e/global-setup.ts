/**
 * Global setup for Playwright E2E tests
 * Ensures LuCI is fully ready before running tests
 */

import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  console.log('🔍 Checking if LuCI is ready...');
  
  const browser = await chromium.launch();
  const page = await browser.newPage();
  
  const baseURL = config.use?.baseURL || 'http://localhost:8080';
  const maxRetries = 30;
  const retryDelay = 2000;
  
  for (let i = 0; i < maxRetries; i++) {
    try {
      console.log(`  Attempt ${i + 1}/${maxRetries}: Checking ${baseURL}/cgi-bin/luci/`);
      
      const response = await page.goto(`${baseURL}/cgi-bin/luci/`, {
        waitUntil: 'domcontentloaded',
        timeout: 10000
      });
      
      // LuCI might return 200 or 403 initially, both are OK as long as we get the login form
      if (response && (response.ok() || response.status() === 403)) {
        // Check if we can actually see login form elements
        const hasLoginForm = await page.locator('#luci_password').isVisible({ timeout: 5000 }).catch(() => false);
        
        if (hasLoginForm) {
          console.log('✅ LuCI is ready and responding correctly!');
          await browser.close();
          return;
        }
        
        console.log(`  ⚠️  HTTP ${response.status()} but login form not found yet...`);
      } else {
        console.log(`  ⚠️  HTTP ${response?.status() || 'unknown'} - retrying...`);
      }
    } catch (error: any) {
      console.log(`  ⚠️  Error: ${error.message} - retrying...`);
    }
    
    if (i < maxRetries - 1) {
      await new Promise(resolve => setTimeout(resolve, retryDelay));
    }
  }
  
  await browser.close();
  throw new Error('❌ LuCI did not become ready in time. Please check if the container is running properly.');
}

export default globalSetup;
