$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$indexPath = Join-Path $projectRoot '.firebase/local-credentials/current-login.json'
if (!(Test-Path -LiteralPath $indexPath)) { throw 'No recovered local login is available.' }
$account = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
$secure = (Get-Content -LiteralPath $account.secretPath -Raw).Trim() | ConvertTo-SecureString
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $form = New-Object Windows.Forms.Form
  $form.Text = 'BrewVerse LOCAL test login - production unchanged'
  $form.Size = New-Object Drawing.Size(560, 265)
  $form.StartPosition = 'CenterScreen'
  $form.TopMost = $true
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $label = New-Object Windows.Forms.Label
  $label.Text = "LOCAL Firebase emulators only. Sign in with this recovered account.`r`nCafe and original UID are preserved."
  $label.Location = New-Object Drawing.Point(15, 15)
  $label.Size = New-Object Drawing.Size(510, 40)
  $email = New-Object Windows.Forms.TextBox
  $email.Text = $account.email
  $email.ReadOnly = $true
  $email.Location = New-Object Drawing.Point(15, 65)
  $email.Width = 510
  $password = New-Object Windows.Forms.TextBox
  $password.Text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  $password.ReadOnly = $true
  $password.UseSystemPasswordChar = $true
  $password.Location = New-Object Drawing.Point(15, 100)
  $password.Width = 510
  $reveal = New-Object Windows.Forms.CheckBox
  $reveal.Text = 'Show local password'
  $reveal.Location = New-Object Drawing.Point(15, 140)
  $reveal.Width = 220
  $reveal.Add_CheckedChanged({ $password.UseSystemPasswordChar = !$reveal.Checked })
  $copy = New-Object Windows.Forms.Button
  $copy.Text = 'Copy password'
  $copy.Location = New-Object Drawing.Point(265, 170)
  $copy.Width = 130
  $copy.Add_Click({ [Windows.Forms.Clipboard]::SetText($password.Text) })
  $close = New-Object Windows.Forms.Button
  $close.Text = 'Close'
  $close.Location = New-Object Drawing.Point(410, 170)
  $close.Width = 115
  $close.Add_Click({ $form.Close() })
  $form.Controls.AddRange(@($label, $email, $password, $reveal, $copy, $close))
  [void]$form.ShowDialog()
  $password.Text = ''
  $form.Dispose()
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  $secure.Dispose()
}
