# Koffein

En minimal macOS-menyradsapp som håller Macen vaken.

## Bygg och kör

```sh
./build-app.sh
```

Skriptet stänger en Koffein som redan körs och öppnar den nya versionen. Appen körs utan Dock-ikon. Klicka på kaffekoppen i menyraden för att slå på eller av, välja hur länge den ska vara aktiv och om skärmen får gå i vila.

Vid första starten läggs Koffein till som inloggningsobjekt och aktiveras direkt, så efter en omstart är den igång utan att du gör något. Båda går att stänga av i menyn. Bygg om på samma plats, annars pekar inloggningsobjektet på den gamla sökvägen.
