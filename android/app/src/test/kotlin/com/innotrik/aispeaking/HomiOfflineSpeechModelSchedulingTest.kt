package com.innotrik.aispeaking

import android.content.Context
import androidx.work.Configuration
import androidx.work.NetworkType
import androidx.work.WorkManager
import androidx.work.impl.WorkManagerImpl
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomiOfflineSpeechModelSchedulingTest {
    private lateinit var context: Context
    private val executor = Executors.newFixedThreadPool(2)
    private val model = HomiOfflineSpeechModels.english

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        try {
            WorkManager.getInstance(context)
        } catch (_: IllegalStateException) {
            WorkManager.initialize(context, Configuration.Builder().setExecutor(executor).build())
        }
        assertTrue(HomiOfflineSpeechModel.isRuntimeSupported())
        assertFalse(HomiOfflineSpeechModel.hasValidatedWifi(context))
    }

    @After
    fun tearDown() {
        WorkManager.getInstance(context).cancelAllWork().result.get(5, TimeUnit.SECONDS)
        WorkManagerImpl.setDelegate(null)
        executor.shutdownNow()
    }

    @Test
    fun repeatedSchedulingKeepsTheSameWifiConstrainedJobAndProgress() {
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        val manager = WorkManager.getInstance(context)
        val first = manager.getWorkInfosForUniqueWork(model.workName).get(5, TimeUnit.SECONDS).single()
        assertEquals(NetworkType.UNMETERED, first.constraints.requiredNetworkType)
        assertTrue(first.constraints.requiresStorageNotLow())
        HomiOfflineSpeechModel.setState(context, model, "downloading", 37)
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        val second = manager.getWorkInfosForUniqueWork(model.workName).get(5, TimeUnit.SECONDS).single()
        assertEquals(first.id, second.id)
        assertEquals(37, HomiOfflineSpeechModel.status(context, model)["progress"])
    }

    @Test
    fun cancellingQueuedDownloadPreservesPartialArchiveAndCanScheduleAgain() {
        val partial = HomiOfflineSpeechModel.archiveFile(context, model)
        partial.parentFile!!.mkdirs()
        partial.writeText("partial-download-fixture")
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        assertTrue(HomiOfflineSpeechModel.isDownloadEnabled(context, model))
        HomiOfflineSpeechModel.cancelDownload(context, model)
        assertFalse(HomiOfflineSpeechModel.isDownloadEnabled(context, model))
        assertEquals("missing", HomiOfflineSpeechModel.status(context, model)["state"])
        assertEquals("partial-download-fixture", partial.readText())
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(model.workName)
            .get(5, TimeUnit.SECONDS).filter { !it.state.isFinished }
        assertEquals(1, work.size)
        assertTrue(HomiOfflineSpeechModel.isDownloadEnabled(context, model))
        assertEquals("partial-download-fixture", partial.readText())
    }

    @Test
    fun cancellingAutomaticDownloadsDoesNotRemoveAnInstalledModel() {
        installFixture()
        HomiOfflineSpeechModel.cancelDownload(context)
        assertTrue(HomiOfflineSpeechModel.isInstalled(context, model))
        assertEquals("installed", HomiOfflineSpeechModel.status(context, model)["state"])
        assertFalse(HomiOfflineSpeechModel.isDownloadEnabled(context, model))
    }

    @Test
    fun readyMarkerAloneCannotMakeAnIncompleteModelUsable() {
        val directory = HomiOfflineSpeechModel.modelDirectory(context, model)
        for (required in listOf("am/final.mdl", "conf/model.conf", "graph/HCLr.fst", "graph/Gr.fst")) {
            installFixture()
            assertTrue(HomiOfflineSpeechModel.isInstalled(context, model))
            File(directory, required).delete()
            assertFalse("Missing $required must invalidate installed status",
                HomiOfflineSpeechModel.isInstalled(context, model))
        }
    }

    private fun installFixture() {
        val directory = HomiOfflineSpeechModel.modelDirectory(context, model)
        for (path in listOf("am/final.mdl", "conf/model.conf", "graph/HCLr.fst", "graph/Gr.fst")) {
            val file = File(directory, path)
            file.parentFile!!.mkdirs()
            file.writeText("fixture")
        }
        File(directory, ".homi-ready").writeText(model.downloadSha256)
    }

    @Test
    fun installedModelNeedsMatchingMarkerAndAllRequiredFiles() {
        val directory = HomiOfflineSpeechModel.modelDirectory(context, model)
        for (path in listOf("am/final.mdl", "conf/model.conf", "graph/HCLr.fst", "graph/Gr.fst")) {
            val file = File(directory, path)
            file.parentFile!!.mkdirs()
            file.writeText("fixture")
        }
        val marker = File(directory, ".homi-ready")
        marker.writeText(model.downloadSha256)
        assertTrue(HomiOfflineSpeechModel.isInstalled(context, model))
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        assertTrue(WorkManager.getInstance(context).getWorkInfosForUniqueWork(model.workName)
            .get(5, TimeUnit.SECONDS).isEmpty())
        marker.writeText("invalid")
        assertFalse(HomiOfflineSpeechModel.isInstalled(context, model))
        HomiOfflineSpeechModel.scheduleDownload(context, model)
        assertEquals(1, WorkManager.getInstance(context).getWorkInfosForUniqueWork(model.workName)
            .get(5, TimeUnit.SECONDS).size)
    }
}
