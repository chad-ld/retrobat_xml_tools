#Retrobat Gamelist Visibility Editor v1.0
#there is a sample gamelist.xml that you can use to test with in the same folder as this script. 
# Load necessary .NET assemblies
Add-Type -AssemblyName PresentationFramework,System.Xml.Linq,PresentationCore,PresentationFramework

# Create the XAML markup for the GUI
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Retrobat Gamelist Visibility Editor" Height="400" Width="800" ResizeMode="CanResizeWithGrip">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ListView Name="lvGames" Margin="10" Grid.Row="0" ItemsSource="{Binding}">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="ID" DisplayMemberBinding="{Binding Id}" Width="50"/>
                    <GridViewColumn Header="Path" DisplayMemberBinding="{Binding Path}" Width="400"/>
                    <GridViewColumn Header="Hidden" DisplayMemberBinding="{Binding Hidden}" Width="100"/>
                    <GridViewColumn Header="Mod?" DisplayMemberBinding="{Binding ModStatus}" Width="80"/>
                </GridView>
            </ListView.View>
        </ListView>
        <StackPanel Orientation="Horizontal" Grid.Row="1">
            <Button Name="btnLoad" Content="Load XML" Width="100" Height="25" Margin="10"/>
            <Button Name="btnToggleHidden" Content="Toggle Hidden" Width="100" Height="25" Margin="10"/>
            <Button Name="btnSave" Content="Save XML" Width="100" Height="25" Margin="10"/>
            <Button Name="btnCopyRomName" Content="Copy ROM Name" Width="120" Height="25" Margin="10"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Grid.Row="2">
            <TextBox Name="txtFilter" Width="150" Height="25" Margin="10"/>
            <Button Name="btnFilter" Content="Filter" Width="100" Height="25" Margin="10"/>
        </StackPanel>
    </Grid>
</Window>
"@


# Create the GUI from the XAML
$reader=(New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$window=[Windows.Markup.XamlReader]::Load($reader)

# Load the System.Windows.Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Get references to controls
$lvGames = $window.FindName("lvGames")
$btnLoad = $window.FindName("btnLoad")
$btnToggleHidden = $window.FindName("btnToggleHidden")
$btnSave = $window.FindName("btnSave")
$btnCopyRomName = $window.FindName("btnCopyRomName")
$txtFilter = $window.FindName("txtFilter")
$btnFilter = $window.FindName("btnFilter")

# Variables to hold the XML data
$xmlData = $null
$selectedGame = $null

# Load button click event
$btnLoad.Add_Click({
    try {
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "XML Files (*.xml)|*.xml"
        $openFileDialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
        $dialogResult = $openFileDialog.ShowDialog()

        if ($dialogResult -eq "OK") {
            $xmlPath = $openFileDialog.FileName
            $script:xmlData = [System.Xml.Linq.XDocument]::Load($xmlPath)
            $gameData = $script:xmlData.Root.Elements("game") | ForEach-Object {
                $gameName = $_.Element("name")?.Value
                $gamePath = $_.Element("path")?.Value
                $gameId = $_.Attribute("id")?.Value
                $hiddenElement = $_.Element("hidden")
                $hiddenStatus = if ($hiddenElement) { $hiddenElement.Value } else { "false" }
                New-Object PSObject -Property @{
                    'Id' = $gameId
                    'Name' = $gameName
                    'Path' = $gamePath
                    'Hidden' = $hiddenStatus
                    'ModStatus' = ""
                }
            }
            $lvGames.ItemsSource = $gameData
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
})

# Toggle Hidden button click event
$btnToggleHidden.Add_Click({
    try {
        $selectedGames = $lvGames.SelectedItems

        if ($selectedGames) {
            foreach ($selectedGame in $selectedGames) {
                $gameId = $selectedGame.Id
                $gamePath = $selectedGame.Path

                $selectedGameXml = $script:xmlData.Descendants("game") | Where-Object {
                    $_.Attribute("id").Value -eq $gameId -and $_.Element("path").Value -eq $gamePath
                } | Select-Object -First 1

                $hiddenElement = $selectedGameXml.Element("hidden")
                if ($hiddenElement) {
                    $hiddenElement.Value = if ($hiddenElement.Value -eq 'true') { 'false' } else { 'true' }
                } else {
                    $newHiddenElement = [System.Xml.Linq.XElement]::new("hidden", "true")
                    $selectedGameXml.Add($newHiddenElement)
                    $hiddenElement = $newHiddenElement
                }

                $selectedGame.Hidden = $hiddenElement.Value
                $selectedGame.ModStatus = "Yes"
            }

            # Fix visual glitch: Refresh the ListView and force the update of the GUI
            $lvGames.Items.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
})

# Save XML button click event
$btnSave.Add_Click({
    try {
        if ($xmlData) {
            $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveFileDialog.Filter = "XML Files (*.xml)|*.xml"
            $saveFileDialog.FileName = [System.IO.Path]::GetFileName($xmlPath)

            if ($saveFileDialog.ShowDialog() -eq "OK") {
                $xmlPath = $saveFileDialog.FileName

                # Create a backup folder if it doesn't exist
                $backupFolder = Join-Path (Split-Path $xmlPath) "gamelist_backup"
                if (!(Test-Path $backupFolder)) {
                    New-Item -ItemType Directory -Path $backupFolder | Out-Null
                }

                # Generate a backup file name with an underscore and a three-digit padded number
                $backupFileNumber = 0
                $backupFileName = [System.IO.Path]::GetFileNameWithoutExtension($xmlPath)
                $backupExtension = [System.IO.Path]::GetExtension($xmlPath)
                $backupFilePath = ""

                do {
                    $backupFileNumber++
                    $backupFileSuffix = "_" + $backupFileNumber.ToString("D3")
                    $backupFilePath = Join-Path $backupFolder ("$backupFileName$backupFileSuffix$backupExtension")
                }
                while (Test-Path $backupFilePath)

                # Copy the XML file to the backup location
                Copy-Item -Path $xmlPath -Destination $backupFilePath -Force

                # Save the updated XML data
                $xmlData.Save($xmlPath, [System.Xml.Linq.SaveOptions]::None)

                # Set ModStatus to "Saved" for all modified items
                foreach ($item in $lvGames.ItemsSource) {
                    if ($item.ModStatus -eq "Yes") {
                        $item.ModStatus = "Saved"
                    }
                }
                $lvGames.Items.Refresh()

                [System.Windows.MessageBox]::Show("XML file saved successfully.", "Success", "OK", "Information")
            }
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
})

# Copy ROM Name button click event
$btnCopyRomName.Add_Click({
    try {
        $selectedGames = $lvGames.SelectedItems

        if ($selectedGames) {
            $romNames = $selectedGames | ForEach-Object { $_.Path.TrimStart("./") }
            $romNames -join "`n" | Set-Clipboard
            [System.Windows.MessageBox]::Show("ROM names copied to clipboard.", "Success", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
})


# Filter button click event
$btnFilter.Add_Click({
    try {
        $filterText = $txtFilter.Text.Trim()
        # Apply filter based on the Path property (case-insensitive and partial match)
        $lvGames.Items.Filter = {
			param($item)
			$item.Path -like "*$filterText*"  -or $item.Path -like "*$filterText*"
			}
        }
    catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", "OK", "Error")
    }
})

# Show the GUI
$window.ShowDialog() | Out-Null
