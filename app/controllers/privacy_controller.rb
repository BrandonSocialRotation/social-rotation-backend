class PrivacyController < ActionController::Base
  protect_from_forgery with: :null_session

  def show
    # Render HTML directly for Meta's crawler
    # This ensures a proper 200 response with complete HTML content
    html_content = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Privacy Policy - Social Rotation</title>
        <meta name="description" content="Social Rotation Privacy Policy. Learn how we collect, use, and protect your personal information.">
        
        <!-- Open Graph / Facebook -->
        <meta property="og:type" content="website">
        <meta property="og:url" content="https://my.socialrotation.app/privacy-policy">
        <meta property="og:title" content="Privacy Policy - Social Rotation">
        <meta property="og:description" content="Social Rotation Privacy Policy. Learn how we collect, use, and protect your personal information.">
        
        <!-- Twitter -->
        <meta property="twitter:card" content="summary_large_image">
        <meta property="twitter:url" content="https://my.socialrotation.app/privacy-policy">
        <meta property="twitter:title" content="Privacy Policy - Social Rotation">
        <meta property="twitter:description" content="Social Rotation Privacy Policy. Learn how we collect, use, and protect your personal information.">
        
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 40px 20px;
            background-color: #f5f5f5;
          }
          .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
          }
          h2 {
            color: #34495e;
            margin-top: 30px;
          }
          p {
            margin-bottom: 15px;
          }
          .last-updated {
            color: #7f8c8d;
            font-style: italic;
            margin-bottom: 30px;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Privacy Policy</h1>
          <p class="last-updated">Last updated: January 21, 2026</p>
          
          <h2>Introduction</h2>
          <p>Social Rotation ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our social media automation and marketing platform.</p>
          
          <h2>Information We Collect</h2>
          <p>We collect information that you provide directly to us, including:</p>
          <ul>
            <li>Account information (name, email address, password)</li>
            <li>Profile information and preferences</li>
            <li>Content you post or schedule through our platform</li>
            <li>Payment information (processed securely through third-party providers)</li>
            <li>Social media account connections and tokens</li>
          </ul>
          
          <h2>How We Use Your Information</h2>
          <p>We use the information we collect to:</p>
          <ul>
            <li>Provide, maintain, and improve our services</li>
            <li>Process transactions and send related information</li>
            <li>Send you technical notices and support messages</li>
            <li>Respond to your comments and questions</li>
            <li>Monitor and analyze usage patterns and trends</li>
            <li>Detect, prevent, and address technical issues</li>
          </ul>
          
          <h2>Information Sharing</h2>
          <p>We do not sell, trade, or rent your personal information to third parties. We may share your information only in the following circumstances:</p>
          <ul>
            <li>With your consent</li>
            <li>To comply with legal obligations</li>
            <li>To protect our rights and safety</li>
            <li>With service providers who assist in operating our platform (under strict confidentiality agreements)</li>
          </ul>
          
          <h2>Data Security</h2>
          <p>We implement appropriate technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. However, no method of transmission over the Internet is 100% secure.</p>
          
          <h2>Your Rights</h2>
          <p>You have the right to:</p>
          <ul>
            <li>Access your personal information</li>
            <li>Correct inaccurate information</li>
            <li>Request deletion of your information</li>
            <li>Object to processing of your information</li>
            <li>Request data portability</li>
          </ul>
          
          <h2>Cookies and Tracking</h2>
          <p>We use cookies and similar tracking technologies to track activity on our platform and hold certain information. You can instruct your browser to refuse all cookies or to indicate when a cookie is being sent.</p>
          
          <h2>Third-Party Services</h2>
          <p>Our platform integrates with third-party services (Facebook, Instagram, Twitter, LinkedIn, etc.). Your use of these services is subject to their respective privacy policies.</p>
          
          <h2>Children's Privacy</h2>
          <p>Our services are not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13.</p>
          
          <h2>Changes to This Policy</h2>
          <p>We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last updated" date.</p>
          
          <h2>Contact Us</h2>
          <p>If you have any questions about this Privacy Policy, please contact us at:</p>
          <p>
            Email: privacy@socialrotation.com<br>
            Website: <a href="https://my.socialrotation.app">https://my.socialrotation.app</a>
          </p>
        </div>
      </body>
      </html>
    HTML

    render html: html_content.html_safe, content_type: 'text/html'
  end
end

